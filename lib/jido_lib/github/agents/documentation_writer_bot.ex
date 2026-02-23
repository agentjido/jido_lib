defmodule Jido.Lib.Github.Agents.DocumentationWriterBot do
  @moduledoc """
  Persistent multi-repo documentation writer bot with writer/critic workflow.
  """

  use Jido.Agent,
    name: "github_documentation_writer_bot",
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

  alias Jido.Lib.Bots.Foundation.Intake
  alias Jido.Lib.Github.Actions
  alias Jido.Lib.Github.Actions.DocsWriter
  alias Jido.Lib.Github.AgentRuntime
  alias Jido.Lib.Github.Helpers
  alias Jido.Lib.Github.Plugins.{Observability, RuntimeContext}
  alias Jido.Runic.ActionNode
  alias Runic.Workflow

  @default_timeout_ms 600_000
  @await_buffer_ms 60_000

  @doc false
  @spec plugin_specs() :: [Jido.Plugin.Spec.t()]
  def plugin_specs do
    [
      Observability.plugin_spec(%{}),
      RuntimeContext.plugin_spec(%{})
    ]
  end

  @doc "Build documentation writer workflow DAG."
  @spec build_workflow() :: Workflow.t()
  def build_workflow do
    decide_v1 =
      ActionNode.new(DocsWriter.DecideRevision, %{iteration: 1}, name: :decide_revision_v1)

    decide_v2 =
      ActionNode.new(DocsWriter.DecideRevision, %{iteration: 2}, name: :decide_revision_v2)

    Workflow.new(name: :github_documentation_writer_bot)
    |> Workflow.add(Actions.node(DocsWriter.ValidateHostEnv))
    |> Workflow.add(Actions.node(DocsWriter.EnsureSpriteSession), to: :validate_host_env)
    |> Workflow.add(Actions.node(Actions.PrepareGithubAuth), to: :ensure_sprite_session)
    |> Workflow.add(Actions.node(DocsWriter.SyncRepos), to: :prepare_github_auth)
    |> Workflow.add(Actions.node(Actions.RunSetupCommands), to: :sync_repos)
    |> Workflow.add(Actions.node(Actions.ValidateRuntime), to: :run_setup_commands)
    |> Workflow.add(Actions.node(DocsWriter.PrepareRoleRuntimes), to: :validate_runtime)
    |> Workflow.add(Actions.node(DocsWriter.BuildDocsBrief), to: :prepare_role_runtimes)
    |> Workflow.add(
      ActionNode.new(DocsWriter.RunWriterPass, %{iteration: 1},
        name: :run_writer_pass_v1,
        executor: {:child, :writer}
      ),
      to: :build_docs_brief
    )
    |> Workflow.add(
      ActionNode.new(DocsWriter.RunCriticPass, %{iteration: 1},
        name: :run_critic_pass_v1,
        executor: {:child, :critic}
      ),
      to: :run_writer_pass_v1
    )
    |> Workflow.add(decide_v1, to: :run_critic_pass_v1)
    |> Workflow.add(
      ActionNode.new(DocsWriter.RunWriterPass, %{iteration: 2},
        name: :run_writer_pass_v2,
        executor: {:child, :writer_v2}
      ),
      to: :decide_revision_v1
    )
    |> Workflow.add(
      ActionNode.new(DocsWriter.RunCriticPass, %{iteration: 2},
        name: :run_critic_pass_v2,
        executor: {:child, :critic_v2}
      ),
      to: :run_writer_pass_v2
    )
    |> Workflow.add(decide_v2, to: :run_critic_pass_v2)
    |> Workflow.add(Actions.node(DocsWriter.FinalizeGuide), to: :decide_revision_v2)
    |> Workflow.add(Actions.node(DocsWriter.PublishGuidePr), to: :finalize_guide)
    |> Workflow.add(Actions.node(Actions.TeardownSprite), to: :publish_guide_pr)
  end

  @doc "Run docs writer workflow from brief text and options."
  @spec run_brief(String.t(), keyword()) :: map()
  def run_brief(brief, opts \\ []) when is_binary(brief) and is_list(opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)
    await_timeout = Keyword.get(opts, :await_timeout, timeout + @await_buffer_ms)
    intake = build_intake(brief, opts)
    jido = Keyword.get(opts, :jido, Jido.default_instance())
    debug = Keyword.get(opts, :debug, true)

    {observer_pid, owns_observer?} = AgentRuntime.ensure_observer(opts, "DocumentationWriter")

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

  @doc "Build docs writer intake payload from brief and options."
  @spec build_intake(String.t(), keyword()) :: map()
  def build_intake(brief, opts \\ []) when is_binary(brief) and is_list(opts) do
    writer_provider = resolve_writer_provider(opts)
    critic_provider = resolve_critic_provider(opts)
    run_id = Intake.normalize_run_id(Keyword.get(opts, :run_id))
    sprite_name = Keyword.get(opts, :sprite_name)
    workspace_root = resolve_workspace_root(opts, sprite_name)
    setup_commands = resolve_setup_commands(opts)
    repos = resolve_repos(opts)
    keep_sprite = resolve_keep_sprite(opts)
    publish = Keyword.get(opts, :publish, false)

    %{
      run_id: run_id,
      brief: brief,
      repos: repos,
      output_repo: Keyword.get(opts, :output_repo),
      output_path: Keyword.get(opts, :output_path),
      publish: publish,
      writer_provider: writer_provider,
      critic_provider: critic_provider,
      provider: writer_provider,
      max_revisions: Keyword.get(opts, :max_revisions, 1),
      sprite_name: sprite_name,
      workspace_root: workspace_root,
      timeout: Keyword.get(opts, :timeout, @default_timeout_ms),
      keep_sprite: keep_sprite,
      keep_workspace: Keyword.get(opts, :keep_workspace, true),
      setup_commands: setup_commands,
      sprite_config:
        Intake.build_sprite_config(
          [writer_provider, critic_provider],
          Keyword.get(opts, :sprite_config)
        ),
      sprites_mod: Keyword.get(opts, :sprites_mod, Sprites),
      shell_agent_mod: Keyword.get(opts, :shell_agent_mod, Jido.Shell.Agent),
      shell_session_mod: Keyword.get(opts, :shell_session_mod, Jido.Shell.ShellSession),
      shell_session_server_mod:
        Keyword.get(opts, :shell_session_server_mod, Jido.Shell.ShellSessionServer),
      branch_prefix: Keyword.get(opts, :branch_prefix, "jido/docs"),
      publish_requested: publish
    }
  end

  defp resolve_writer_provider(opts) do
    Intake.normalize_provider!(
      Keyword.get(opts, :writer_provider, Keyword.get(opts, :writer, :codex)),
      :codex
    )
  end

  defp resolve_critic_provider(opts) do
    Intake.normalize_provider!(
      Keyword.get(opts, :critic_provider, Keyword.get(opts, :critic, :claude)),
      :claude
    )
  end

  defp resolve_workspace_root(opts, sprite_name) do
    case Keyword.get(opts, :workspace_root) do
      value when is_binary(value) and value != "" ->
        value

      _ when is_binary(sprite_name) and sprite_name != "" ->
        "/work/docs/#{sprite_name}"

      _ ->
        nil
    end
  end

  defp resolve_setup_commands(opts) do
    opts
    |> Keyword.get(:setup_commands, Keyword.get(opts, :setup_cmd, []))
    |> Intake.normalize_commands()
  end

  defp resolve_repos(opts) do
    case Keyword.get_values(opts, :repo) do
      [] -> Intake.normalize_commands(Keyword.get(opts, :repos, []))
      values -> Intake.normalize_commands(values)
    end
  end

  defp resolve_keep_sprite(opts) do
    case Keyword.fetch(opts, :keep_sprite) do
      {:ok, value} -> value == true
      :error -> true
    end
  end

  @doc "Build a `runic.feed` signal from intake payload."
  @spec intake_signal(map()) :: Jido.Signal.t()
  def intake_signal(payload) when is_map(payload) do
    Jido.Signal.new!("runic.feed", %{data: payload}, source: "/github/documentation_writer_bot")
  end

  @doc "Run docs writer bot from intake map."
  @spec run(map(), keyword()) :: {:ok, map()} | {:error, term(), map()} | {:error, term()}
  def run(intake, opts \\ []) when is_map(intake) and is_list(opts) do
    intake = normalize_intake!(intake)
    jido = Keyword.fetch!(opts, :jido)
    timeout = Keyword.get(opts, :timeout, Helpers.map_get(intake, :timeout, @default_timeout_ms))

    case AgentRuntime.run_pipeline(__MODULE__, intake,
           jido: jido,
           timeout: timeout,
           debug: Keyword.get(opts, :debug, true),
           observer_pid: Keyword.get(opts, :observer_pid),
           sprite_prefix: "jido-docs"
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

  defp normalize_intake!(intake) when is_map(intake) do
    writer_provider =
      Intake.normalize_provider!(Helpers.map_get(intake, :writer_provider, :codex), :codex)

    critic_provider =
      Intake.normalize_provider!(Helpers.map_get(intake, :critic_provider, :claude), :claude)

    intake
    |> Map.put(:writer_provider, writer_provider)
    |> Map.put(:critic_provider, critic_provider)
    |> Map.put(:provider, writer_provider)
    |> Map.put_new(:keep_sprite, true)
    |> Map.put_new(:publish, false)
    |> Map.put_new(:publish_requested, Helpers.map_get(intake, :publish, false))
    |> Map.put_new(:branch_prefix, "jido/docs")
  end

  defp result_map(intake, run, final) do
    %{
      status: run.status,
      run_id: Helpers.map_get(final, :run_id, Helpers.map_get(intake, :run_id)),
      writer_provider:
        Helpers.map_get(final, :writer_provider, Helpers.map_get(intake, :writer_provider)),
      critic_provider:
        Helpers.map_get(final, :critic_provider, Helpers.map_get(intake, :critic_provider)),
      decision: result_value(final, run.productions, :decision),
      iterations_used: result_value(final, run.productions, :iterations_used, 1),
      final_guide: result_value(final, run.productions, :final_guide),
      repo_contexts: result_value(final, run.productions, :repo_contexts, []),
      output_repo:
        result_value(
          final,
          run.productions,
          :output_repo,
          get_in(Helpers.map_get(intake, :output_repo_context, %{}), [:alias])
        ),
      output_path: result_value(final, run.productions, :output_path),
      publish_requested:
        result_value(
          final,
          run.productions,
          :publish_requested,
          Helpers.map_get(intake, :publish)
        ),
      published: result_value(final, run.productions, :published, false),
      branch_name: result_value(final, run.productions, :branch_name),
      commit_sha: result_value(final, run.productions, :commit_sha),
      pr_url: result_value(final, run.productions, :pr_url),
      pr_number: result_value(final, run.productions, :pr_number),
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
