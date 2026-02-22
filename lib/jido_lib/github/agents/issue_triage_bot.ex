defmodule Jido.Lib.Github.Agents.IssueTriageBot do
  @moduledoc """
  Canonical GitHub issue triage bot.

  This module is both:
  - the Runic orchestrator agent definition, and
  - the public intake/run API (`triage/2`, `run/2`).
  """

  use Jido.Agent,
    name: "github_issue_triage_bot",
    strategy: {Jido.Runic.Strategy, workflow_fn: &__MODULE__.build_workflow/0},
    schema: []

  alias Jido.Lib.Bots.Foundation.Intake
  alias Jido.Lib.Bots.Runtime
  alias Jido.Lib.Github.Actions
  alias Jido.Lib.Github.AgentRuntime
  alias Jido.Lib.Github.Helpers
  alias Jido.Lib.Github.Plugins.{Observability, RuntimeContext}
  alias Jido.Lib.Github.ResultMaps
  alias Runic.Workflow

  @default_timeout_ms 300_000
  @await_buffer_ms 60_000

  @type triage_response :: %{
          issue_url: String.t(),
          intake: map(),
          status: :completed | :failed | :error,
          result: map() | nil,
          error: term() | nil,
          productions: [map()],
          facts: [Runic.Workflow.Fact.t()],
          events: [map()],
          failures: [map()],
          pid: pid() | nil
        }

  @doc false
  @spec plugin_specs() :: [Jido.Plugin.Spec.t()]
  def plugin_specs do
    [
      Observability.plugin_spec(%{}),
      RuntimeContext.plugin_spec(%{})
    ]
  end

  @doc "Build the sprite triage DAG with provider-neutral coding execution."
  @spec build_workflow() :: Workflow.t()
  def build_workflow do
    Workflow.new(name: :github_issue_triage_bot)
    |> Workflow.add(Actions.node(Actions.ValidateHostEnv))
    |> Workflow.add(Actions.node(Actions.ProvisionSprite), to: :validate_host_env)
    |> Workflow.add(Actions.node(Actions.PrepareGithubAuth), to: :provision_sprite)
    |> Workflow.add(Actions.node(Actions.FetchIssue), to: :prepare_github_auth)
    |> Workflow.add(Actions.node(Actions.CloneRepo), to: :fetch_issue)
    |> Workflow.add(Actions.node(Actions.RunSetupCommands), to: :clone_repo)
    |> Workflow.add(Actions.node(Actions.ValidateRuntime), to: :run_setup_commands)
    |> Workflow.add(Actions.node(Actions.PrepareProviderRuntime), to: :validate_runtime)
    |> Workflow.add(Actions.node(Actions.RunCodingAgent), to: :prepare_provider_runtime)
    |> Workflow.add(Actions.node(Actions.PostIssueComment), to: :run_coding_agent)
    |> Workflow.add(Actions.node(Actions.TeardownSprite), to: :post_issue_comment)
  end

  @doc """
  Run triage for a GitHub issue URL.
  """
  @spec triage(String.t(), keyword()) :: triage_response()
  def triage(issue_url, opts \\ []) when is_binary(issue_url) do
    jido = Keyword.get(opts, :jido, Jido.default_instance())
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)
    await_timeout = Keyword.get(opts, :await_timeout, timeout + @await_buffer_ms)
    debug = Keyword.get(opts, :debug, true)

    intake =
      build_intake(issue_url,
        provider: Keyword.get(opts, :provider, :claude),
        timeout: timeout,
        keep_sprite: Keyword.get(opts, :keep_sprite, false),
        setup_commands: Keyword.get(opts, :setup_commands, []),
        run_id: Keyword.get(opts, :run_id),
        keep_workspace: Keyword.get(opts, :keep_workspace, false),
        prompt: Keyword.get(opts, :prompt),
        sprite_config: Keyword.get(opts, :sprite_config),
        sprites_mod: Keyword.get(opts, :sprites_mod),
        shell_agent_mod: Keyword.get(opts, :shell_agent_mod),
        shell_session_mod: Keyword.get(opts, :shell_session_mod)
      )

    {observer_pid, owns_observer?} = AgentRuntime.ensure_observer(opts, "IssueTriage")

    try do
      case run_pipeline(intake,
             jido: jido,
             timeout: await_timeout,
             observer_pid: observer_pid,
             debug: debug
           ) do
        {:ok, %{status: :completed} = run} ->
          result =
            ResultMaps.triage_result(
              intake,
              AgentRuntime.extract_final_production(run.productions),
              run.productions
            )

          response(issue_url, intake, :completed, result, nil, run)

        {:ok, %{status: :failed, error: error} = run} ->
          response(issue_url, intake, :failed, nil, error, run)

        {:error, reason, run} ->
          response(issue_url, intake, :error, nil, reason, run)
      end
    after
      if owns_observer?, do: AgentRuntime.stop_observer(observer_pid)
    end
  end

  @doc """
  Run triage from an already-built intake map.
  """
  @spec run(map() | struct(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(intake, opts \\ [])

  def run(%{__struct__: _} = intake, opts), do: run(Map.from_struct(intake), opts)

  def run(intake, opts) when is_map(intake) do
    intake = normalize_intake_provider!(intake)
    jido = Keyword.fetch!(opts, :jido)
    timeout = Keyword.get(opts, :timeout, Helpers.map_get(intake, :timeout, @default_timeout_ms))
    observer_pid = Keyword.get(opts, :observer_pid) || Helpers.map_get(intake, :observer_pid)
    debug = Keyword.get(opts, :debug, true)

    case run_pipeline(intake,
           jido: jido,
           timeout: timeout,
           observer_pid: observer_pid,
           debug: debug
         ) do
      {:ok, %{status: :completed} = run} ->
        final = AgentRuntime.extract_final_production(run.productions)
        {:ok, ResultMaps.triage_result(intake, final, run.productions)}

      {:ok, %{status: :failed, error: error}} ->
        {:error, error || :pipeline_failed}

      {:error, reason, _run} ->
        {:error, reason}
    end
  end

  @doc """
  Build a `runic.feed` intake signal.
  """
  @spec intake_signal(String.t(), keyword()) :: Jido.Signal.t()
  def intake_signal(issue_url, opts) when is_binary(issue_url) and is_list(opts) do
    issue_url
    |> build_intake(opts)
    |> intake_signal()
  end

  @spec intake_signal(map()) :: Jido.Signal.t()
  def intake_signal(payload) when is_map(payload) do
    Jido.Signal.new!(
      "runic.feed",
      %{data: payload},
      source: "/github/issue_triage_bot"
    )
  end

  @doc """
  Build intake attrs from an issue URL and options.
  """
  @spec build_intake(String.t(), keyword()) :: map()
  def build_intake(issue_url, opts \\ []) when is_binary(issue_url) and is_list(opts) do
    {owner, repo, issue_number} = parse_issue_url(issue_url)
    build_intake_attrs(owner, repo, issue_number, issue_url, opts)
  end

  @doc """
  Build intake attrs when owner/repo/issue number are already parsed.
  """
  @spec build_intake_attrs(String.t(), String.t(), integer(), String.t(), keyword()) :: map()
  def build_intake_attrs(owner, repo, issue_number, issue_url, opts \\ [])
      when is_binary(owner) and is_binary(repo) and is_integer(issue_number) and
             is_binary(issue_url) and is_list(opts) do
    provider = Intake.normalize_provider!(Keyword.get(opts, :provider, :claude), :claude)
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)
    run_id = Intake.normalize_run_id(Keyword.get(opts, :run_id))

    setup_commands =
      opts
      |> Keyword.get(:setup_commands, Keyword.get(opts, :setup_cmd, []))
      |> Intake.normalize_commands()

    sprite_config = Intake.build_sprite_config(provider, Keyword.get(opts, :sprite_config))

    %{
      provider: provider,
      agent_mode: :triage,
      owner: owner,
      repo: repo,
      issue_number: issue_number,
      issue_url: issue_url,
      run_id: run_id,
      timeout: timeout,
      keep_workspace: Keyword.get(opts, :keep_workspace, false),
      keep_sprite: Keyword.get(opts, :keep_sprite, false),
      setup_commands: setup_commands,
      prompt: Keyword.get(opts, :prompt),
      comment_mode: :triage_report,
      sprite_config: sprite_config,
      sprites_mod: Keyword.get(opts, :sprites_mod, Sprites),
      shell_agent_mod: Keyword.get(opts, :shell_agent_mod, Jido.Shell.Agent),
      shell_session_mod: Keyword.get(opts, :shell_session_mod, Jido.Shell.ShellSession)
    }
  end

  @doc """
  Parse `https://github.com/<owner>/<repo>/issues/<number>` URL format.
  """
  @spec parse_issue_url(String.t()) :: {String.t(), String.t(), integer()}
  def parse_issue_url(url) when is_binary(url), do: Helpers.parse_issue_url!(url)

  defp run_pipeline(intake, opts) do
    Runtime.run_pipeline(__MODULE__, intake,
      jido: Keyword.fetch!(opts, :jido),
      timeout: Keyword.fetch!(opts, :timeout),
      debug: Keyword.get(opts, :debug, true),
      observer_pid: Keyword.get(opts, :observer_pid),
      sprite_prefix: "jido-triage"
    )
  end

  defp response(issue_url, intake, status, result, error, run) do
    %{
      issue_url: issue_url,
      intake: intake,
      status: status,
      result: result,
      error: error,
      productions: run.productions,
      facts: run.facts,
      events: run.events,
      failures: run.failures,
      pid: run.pid
    }
  end

  defp normalize_intake_provider!(intake) when is_map(intake) do
    provider = Intake.normalize_provider!(Helpers.map_get(intake, :provider, :claude), :claude)
    agent_mode = normalize_agent_mode(Helpers.map_get(intake, :agent_mode, :triage), :triage)

    intake
    |> Map.put(:provider, provider)
    |> Map.put(:agent_mode, agent_mode)
    |> Map.put_new(:comment_mode, :triage_report)
  end

  defp normalize_agent_mode(:triage, _fallback), do: :triage
  defp normalize_agent_mode(:coding, _fallback), do: :coding
  defp normalize_agent_mode("triage", _fallback), do: :triage
  defp normalize_agent_mode("coding", _fallback), do: :coding
  defp normalize_agent_mode(_other, fallback), do: fallback
end
