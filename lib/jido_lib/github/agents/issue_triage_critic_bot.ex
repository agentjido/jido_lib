defmodule Jido.Lib.Github.Agents.IssueTriageCriticBot do
  @moduledoc """
  Dual-role issue triage bot using writer and critic agents in a single Runic workflow.
  """

  use Jido.Agent,
    name: "github_issue_triage_critic_bot",
    strategy:
      {Jido.Runic.Strategy,
       workflow_fn: &__MODULE__.build_workflow/0,
       child_modules: %{
         writer: Jido.Runic.ChildWorker,
         critic: Jido.Runic.ChildWorker,
         writer_v2: Jido.Runic.ChildWorker,
         critic_v2: Jido.Runic.ChildWorker
       }},
    schema: []

  alias Jido.Lib.Bots.Foundation.RunContext
  alias Jido.Lib.Github.Actions
  alias Jido.Lib.Github.Actions.TriageCritic
  alias Jido.Lib.Github.AgentRuntime
  alias Jido.Lib.Github.Helpers
  alias Jido.Lib.Github.Plugins.{Observability, RuntimeContext}
  alias Jido.Runic.ActionNode
  alias Runic.Workflow

  @default_timeout_ms 420_000
  @await_buffer_ms 60_000

  @doc false
  @spec plugin_specs() :: [Jido.Plugin.Spec.t()]
  def plugin_specs do
    [
      Observability.plugin_spec(%{}),
      RuntimeContext.plugin_spec(%{})
    ]
  end

  @doc "Build the issue triage critic workflow DAG."
  @spec build_workflow() :: Workflow.t()
  def build_workflow do
    decide_v1 =
      ActionNode.new(TriageCritic.DecideRevision, %{iteration: 1}, name: :decide_revision_v1)

    decide_v2 =
      ActionNode.new(TriageCritic.DecideRevision, %{iteration: 2}, name: :decide_revision_v2)

    Workflow.new(name: :github_issue_triage_critic_bot)
    |> Workflow.add(Actions.node(Actions.ValidateHostEnv))
    |> Workflow.add(Actions.node(Actions.ProvisionSprite), to: :validate_host_env)
    |> Workflow.add(Actions.node(Actions.PrepareGithubAuth), to: :provision_sprite)
    |> Workflow.add(Actions.node(Actions.FetchIssue), to: :prepare_github_auth)
    |> Workflow.add(Actions.node(Actions.CloneRepo), to: :fetch_issue)
    |> Workflow.add(Actions.node(Actions.RunSetupCommands), to: :clone_repo)
    |> Workflow.add(Actions.node(Actions.ValidateRuntime), to: :run_setup_commands)
    |> Workflow.add(Actions.node(TriageCritic.PrepareRoleRuntimes), to: :validate_runtime)
    |> Workflow.add(Actions.node(TriageCritic.BuildIssueBrief), to: :prepare_role_runtimes)
    |> Workflow.add(
      ActionNode.new(TriageCritic.RunWriterPass, %{iteration: 1},
        name: :run_writer_pass_v1,
        executor: {:child, :writer}
      ),
      to: :build_issue_brief
    )
    |> Workflow.add(
      ActionNode.new(TriageCritic.RunCriticPass, %{iteration: 1},
        name: :run_critic_pass_v1,
        executor: {:child, :critic}
      ),
      to: :run_writer_pass_v1
    )
    |> Workflow.add(decide_v1, to: :run_critic_pass_v1)
    |> Workflow.add(
      ActionNode.new(TriageCritic.RunWriterPass, %{iteration: 2},
        name: :run_writer_pass_v2,
        executor: {:child, :writer_v2}
      ),
      to: :decide_revision_v1
    )
    |> Workflow.add(
      ActionNode.new(TriageCritic.RunCriticPass, %{iteration: 2},
        name: :run_critic_pass_v2,
        executor: {:child, :critic_v2}
      ),
      to: :run_writer_pass_v2
    )
    |> Workflow.add(decide_v2, to: :run_critic_pass_v2)
    |> Workflow.add(Actions.node(TriageCritic.FinalizeComment), to: :decide_revision_v2)
    |> Workflow.add(Actions.node(Actions.TeardownSprite), to: :finalize_comment)
  end

  @doc "Run issue triage/critic workflow for a GitHub issue URL."
  @spec run_issue(String.t(), keyword()) :: map()
  def run_issue(issue_url, opts \\ []) when is_binary(issue_url) and is_list(opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)
    await_timeout = Keyword.get(opts, :await_timeout, timeout + @await_buffer_ms)

    intake =
      build_intake(issue_url,
        writer_provider: Keyword.get(opts, :writer_provider, Keyword.get(opts, :writer, :claude)),
        critic_provider: Keyword.get(opts, :critic_provider, Keyword.get(opts, :critic, :codex)),
        max_revisions: Keyword.get(opts, :max_revisions, 1),
        post_comment: Keyword.get(opts, :post_comment, true),
        timeout: timeout,
        keep_sprite: Keyword.get(opts, :keep_sprite, false),
        keep_workspace: Keyword.get(opts, :keep_workspace, false),
        setup_commands: Keyword.get(opts, :setup_commands, []),
        run_id: Keyword.get(opts, :run_id),
        prompt: Keyword.get(opts, :prompt),
        sprite_config: Keyword.get(opts, :sprite_config),
        sprites_mod: Keyword.get(opts, :sprites_mod),
        shell_agent_mod: Keyword.get(opts, :shell_agent_mod),
        shell_session_mod: Keyword.get(opts, :shell_session_mod),
        observer_pid: Keyword.get(opts, :observer_pid)
      )

    jido = Keyword.get(opts, :jido, Jido.default_instance())
    debug = Keyword.get(opts, :debug, true)

    {observer_pid, owns_observer?} = AgentRuntime.ensure_observer(opts, "IssueTriageCritic")

    try do
      case run(intake,
             jido: jido,
             timeout: await_timeout,
             observer_pid: observer_pid,
             debug: debug
           ) do
        {:ok, result} -> Map.put(result, :status, :completed)
        {:error, reason, partial} -> Map.put(partial, :error, reason)
        {:error, reason} -> %{status: :error, error: reason, run_id: intake[:run_id]}
      end
    after
      if owns_observer?, do: AgentRuntime.stop_observer(observer_pid)
    end
  end

  @doc "Run triage critic bot from intake map."
  @spec run(map(), keyword()) :: {:ok, map()} | {:error, term(), map()} | {:error, term()}
  def run(intake, opts \\ []) when is_map(intake) and is_list(opts) do
    jido = Keyword.fetch!(opts, :jido)
    timeout = Keyword.get(opts, :timeout, Helpers.map_get(intake, :timeout, @default_timeout_ms))

    case AgentRuntime.run_pipeline(__MODULE__, intake,
           jido: jido,
           timeout: timeout,
           debug: Keyword.get(opts, :debug, true),
           observer_pid: Keyword.get(opts, :observer_pid),
           sprite_prefix: "jido-triage-critic"
         ) do
      {:ok, run} ->
        final = AgentRuntime.extract_final_production(run.productions)
        {:ok, result_map(intake, run, final)}

      {:error, reason, run} ->
        final = AgentRuntime.extract_final_production(run.productions)
        {:error, reason, result_map(intake, run, final)}
    end
  rescue
    error ->
      {:error, error}
  end

  @doc "Build triage-critic intake payload from issue URL and options."
  @spec build_intake(String.t(), keyword()) :: map()
  def build_intake(issue_url, opts \\ []) when is_binary(issue_url) and is_list(opts) do
    context =
      RunContext.from_issue_url(issue_url, opts)
      |> case do
        {:ok, context} ->
          context

        {:error, reason} ->
          raise ArgumentError, "invalid triage critic intake: #{inspect(reason)}"
      end

    RunContext.to_intake(context)
  end

  @doc "Build a `runic.feed` signal from intake payload."
  @spec intake_signal(map()) :: Jido.Signal.t()
  def intake_signal(payload) when is_map(payload) do
    Jido.Signal.new!("runic.feed", %{data: payload}, source: "/github/issue_triage_critic_bot")
  end

  defp result_map(intake, run, final) do
    %{
      status: run.status,
      run_id: Helpers.map_get(final, :run_id, Helpers.map_get(intake, :run_id)),
      issue_url: Helpers.map_get(intake, :issue_url),
      writer_provider:
        Helpers.map_get(final, :writer_provider, Helpers.map_get(intake, :writer_provider)),
      critic_provider:
        Helpers.map_get(final, :critic_provider, Helpers.map_get(intake, :critic_provider)),
      decision: result_value(final, run.productions, :decision),
      iterations_used: result_value(final, run.productions, :iterations_used, 1),
      final_comment: result_value(final, run.productions, :final_comment),
      comment_posted: result_value(final, run.productions, :comment_posted),
      comment_url: result_value(final, run.productions, :comment_url),
      artifacts: result_value(final, run.productions, :artifacts, %{}),
      productions: run.productions,
      facts: run.facts,
      events: run.events,
      failures: run.failures,
      error: run.error,
      pid: run.pid
    }
  end

  defp result_value(final, productions, key, default \\ nil)
       when is_map(final) and is_list(productions) and is_atom(key) do
    case Helpers.map_get(final, key) do
      nil ->
        case production_value(productions, key) do
          nil -> default
          value -> value
        end

      value ->
        value
    end
  end

  defp production_value(productions, key) when is_list(productions) and is_atom(key) do
    Enum.find_value(Enum.reverse(productions), fn
      value when is_map(value) -> Helpers.map_get(value, key)
      _ -> nil
    end)
  end
end
