defmodule Jido.Lib.Github.Agents.PrBot do
  @moduledoc """
  Sprite-first GitHub pull request bot.

  This module is the canonical API and orchestrator:
  - parses issue URL intake
  - runs the Runic workflow
  - returns a machine-readable result map
  """

  use Jido.Agent,
    name: "github_pr_bot",
    strategy: {Jido.Runic.Strategy, workflow_fn: &__MODULE__.build_workflow/0},
    schema: []

  alias Jido.Lib.Github.Actions
  alias Jido.Lib.Github.Actions.ValidateHostEnv
  alias Jido.Lib.Github.AgentRuntime
  alias Jido.Lib.Github.Helpers
  alias Jido.Lib.Github.ResultMaps
  alias Runic.Workflow

  @default_timeout_ms 900_000
  @await_buffer_ms 60_000
  @default_check_commands ["mix test --exclude integration"]

  @doc false
  @spec plugin_specs() :: [Jido.Plugin.Spec.t()]
  def plugin_specs, do: []

  @doc """
  Build the PR workflow graph with provider-neutral coding execution.
  """
  @spec build_workflow() :: Workflow.t()
  def build_workflow do
    Workflow.new(name: :github_pr_bot)
    |> Workflow.add(Actions.node(Actions.ValidateHostEnv))
    |> Workflow.add(Actions.node(Actions.ProvisionSprite), to: :validate_host_env)
    |> Workflow.add(Actions.node(Actions.PrepareGithubAuth), to: :provision_sprite)
    |> Workflow.add(Actions.node(Actions.FetchIssue), to: :prepare_github_auth)
    |> Workflow.add(Actions.node(Actions.CloneRepo), to: :fetch_issue)
    |> Workflow.add(Actions.node(Actions.RunSetupCommands), to: :clone_repo)
    |> Workflow.add(Actions.node(Actions.ValidateRuntime), to: :run_setup_commands)
    |> Workflow.add(Actions.node(Actions.PrepareProviderRuntime), to: :validate_runtime)
    |> Workflow.add(Actions.node(Actions.EnsureBranch), to: :prepare_provider_runtime)
    |> Workflow.add(Actions.node(Actions.RunCodingAgent), to: :ensure_branch)
    |> Workflow.add(Actions.node(Actions.EnsureCommit), to: :run_coding_agent)
    |> Workflow.add(Actions.node(Actions.RunCheckCommands), to: :ensure_commit)
    |> Workflow.add(Actions.node(Actions.PushBranch), to: :run_check_commands)
    |> Workflow.add(Actions.node(Actions.CreatePullRequest), to: :push_branch)
    |> Workflow.add(Actions.node(Actions.PostIssueComment), to: :create_pull_request)
    |> Workflow.add(Actions.node(Actions.TeardownSprite), to: :post_issue_comment)
  end

  @doc """
  Parse issue URL, run the PR bot workflow, and return final result map.
  """
  @spec run_issue(String.t(), keyword()) :: map()
  def run_issue(issue_url, opts \\ []) when is_binary(issue_url) do
    jido = Keyword.get(opts, :jido, Jido.default_instance())
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)
    await_timeout = Keyword.get(opts, :await_timeout, timeout + @await_buffer_ms)
    debug = Keyword.get(opts, :debug, true)

    intake =
      build_intake(issue_url,
        provider: Keyword.get(opts, :provider, :claude),
        timeout: timeout,
        keep_sprite: Keyword.get(opts, :keep_sprite, false),
        keep_workspace: Keyword.get(opts, :keep_workspace, false),
        setup_commands: Keyword.get(opts, :setup_commands, Keyword.get(opts, :setup_cmd, [])),
        check_commands:
          Keyword.get(
            opts,
            :check_commands,
            Keyword.get(opts, :check_cmd, @default_check_commands)
          ),
        run_id: Keyword.get(opts, :run_id),
        base_branch: Keyword.get(opts, :base_branch),
        branch_prefix: Keyword.get(opts, :branch_prefix, "jido/prbot"),
        sprite_config: Keyword.get(opts, :sprite_config),
        sprites_mod: Keyword.get(opts, :sprites_mod),
        shell_agent_mod: Keyword.get(opts, :shell_agent_mod),
        shell_session_mod: Keyword.get(opts, :shell_session_mod)
      )

    {observer_pid, owns_observer?} = AgentRuntime.ensure_observer(opts, "PrBot")

    try do
      case run(intake,
             jido: jido,
             timeout: await_timeout,
             observer_pid: observer_pid,
             debug: debug
           ) do
        {:ok, result} ->
          Map.merge(result, %{status: :completed, error: nil})

        {:error, reason, partial} when is_map(partial) ->
          partial
          |> Map.merge(ResultMaps.default_pr_result(intake))
          |> Map.merge(partial)
          |> Map.put(:status, :failed)
          |> Map.put(:error, reason)
      end
    after
      if owns_observer?, do: AgentRuntime.stop_observer(observer_pid)
    end
  end

  @doc """
  Execute the workflow using an intake map payload.
  """
  @spec run(map(), keyword()) :: {:ok, map()} | {:error, term(), map()}
  def run(intake, opts \\ []) when is_map(intake) and is_list(opts) do
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
        {:ok, ResultMaps.pr_result(intake, final, run.productions)}

      {:ok, %{status: :failed} = run} ->
        final = AgentRuntime.extract_final_production(run.productions)

        {:error, {:pipeline_failed, run.failures},
         ResultMaps.pr_result(intake, final, run.productions)}

      {:error, reason, run} ->
        final = AgentRuntime.extract_final_production(run.productions)
        {:error, reason, ResultMaps.pr_result(intake, final, run.productions)}
    end
  end

  @doc """
  Build intake payload map from issue URL and options.
  """
  @spec build_intake(String.t(), keyword()) :: map()
  def build_intake(issue_url, opts \\ []) when is_binary(issue_url) and is_list(opts) do
    {owner, repo, issue_number} = parse_issue_url(issue_url)
    provider = Helpers.provider_normalize!(Keyword.get(opts, :provider, :claude))
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)
    run_id = normalize_run_id(Keyword.get(opts, :run_id))

    sprite_config =
      case Keyword.get(opts, :sprite_config) do
        %{} = config ->
          config

        _ ->
          %{
            token: System.get_env("SPRITES_TOKEN"),
            create: true,
            env: ValidateHostEnv.build_sprite_env(provider)
          }
      end

    %{
      provider: provider,
      agent_mode: :coding,
      comment_mode: :pr_link,
      issue_url: issue_url,
      owner: owner,
      repo: repo,
      issue_number: issue_number,
      run_id: run_id,
      timeout: timeout,
      keep_sprite: Keyword.get(opts, :keep_sprite, false),
      keep_workspace: Keyword.get(opts, :keep_workspace, false),
      setup_commands: Keyword.get(opts, :setup_commands, []),
      check_commands: Keyword.get(opts, :check_commands, @default_check_commands),
      base_branch: Keyword.get(opts, :base_branch),
      branch_prefix: Keyword.get(opts, :branch_prefix, "jido/prbot"),
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

  @doc """
  Build a `runic.feed` signal from intake payload.
  """
  @spec intake_signal(map()) :: Jido.Signal.t()
  def intake_signal(payload) when is_map(payload) do
    Jido.Signal.new!("runic.feed", %{data: payload}, source: "/github/pr_bot")
  end

  defp run_pipeline(intake, opts) do
    AgentRuntime.run_pipeline(__MODULE__, intake,
      jido: Keyword.fetch!(opts, :jido),
      timeout: Keyword.fetch!(opts, :timeout),
      debug: Keyword.get(opts, :debug, true),
      observer_pid: Keyword.get(opts, :observer_pid),
      sprite_prefix: "jido-prbot"
    )
  end

  defp generate_run_id do
    :crypto.strong_rand_bytes(6)
    |> Base.encode16(case: :lower)
  end

  defp normalize_run_id(run_id) when is_binary(run_id) do
    if String.trim(run_id) == "", do: generate_run_id(), else: run_id
  end

  defp normalize_run_id(_), do: generate_run_id()

  defp normalize_intake_provider!(intake) when is_map(intake) do
    provider = Helpers.provider_normalize!(Helpers.map_get(intake, :provider, :claude))
    agent_mode = normalize_agent_mode(Helpers.map_get(intake, :agent_mode, :coding), :coding)

    intake
    |> Map.put(:provider, provider)
    |> Map.put(:agent_mode, agent_mode)
    |> Map.put_new(:comment_mode, :pr_link)
  end

  defp normalize_agent_mode(:triage, _fallback), do: :triage
  defp normalize_agent_mode(:coding, _fallback), do: :coding
  defp normalize_agent_mode("triage", _fallback), do: :triage
  defp normalize_agent_mode("coding", _fallback), do: :coding
  defp normalize_agent_mode(_other, fallback), do: fallback
end
