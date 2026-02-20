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

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.Lib.Github.Actions.IssueTriage
  alias Jido.Lib.Github.Actions.IssueTriage.ValidateHostEnv
  alias Jido.Lib.Github.Actions.PrBot, as: PrActions
  alias Jido.Lib.Github.IssueTriage.SpriteTeardown
  alias Runic.Workflow

  @default_timeout_ms 900_000
  @await_buffer_ms 60_000
  @default_check_commands ["mix test --exclude integration"]
  @delta_log_every 200
  @supported_providers [:claude, :amp, :codex, :gemini]

  @doc false
  @spec plugin_specs() :: [Jido.Plugin.Spec.t()]
  def plugin_specs, do: []

  @doc """
  Build the PR workflow graph with provider-neutral coding execution.
  """
  @spec build_workflow() :: Workflow.t()
  def build_workflow do
    Workflow.new(name: :github_pr_bot)
    |> Workflow.add(IssueTriage.ValidateHostEnv)
    |> Workflow.add(IssueTriage.ProvisionSprite, to: :validate_host_env)
    |> Workflow.add(IssueTriage.PrepareGithubAuth, to: :provision_sprite)
    |> Workflow.add(IssueTriage.FetchIssue, to: :prepare_github_auth)
    |> Workflow.add(IssueTriage.CloneRepo, to: :fetch_issue)
    |> Workflow.add(IssueTriage.SetupRepo, to: :clone_repo)
    |> Workflow.add(IssueTriage.ValidateRuntime, to: :setup_repo)
    |> Workflow.add(IssueTriage.PrepareProviderRuntime, to: :validate_runtime)
    |> Workflow.add(PrActions.EnsureBranch, to: :prepare_provider_runtime)
    |> Workflow.add(PrActions.RunCodingAgent, to: :ensure_branch)
    |> Workflow.add(PrActions.EnsureCommit, to: :run_coding_agent)
    |> Workflow.add(PrActions.RunChecks, to: :ensure_commit)
    |> Workflow.add(PrActions.PushBranch, to: :run_checks)
    |> Workflow.add(PrActions.CreatePullRequest, to: :push_branch)
    |> Workflow.add(PrActions.CommentIssueWithPr, to: :create_pull_request)
    |> Workflow.add(IssueTriage.TeardownSprite, to: :comment_issue_with_pr)
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

    {observer_pid, owns_observer?} = ensure_observer(opts)

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
          |> Map.merge(default_result(intake))
          |> Map.merge(partial)
          |> Map.put(:status, :failed)
          |> Map.put(:error, reason)
      end
    after
      if owns_observer?, do: stop_observer(observer_pid)
    end
  end

  @doc """
  Execute the workflow using an intake map payload.
  """
  @spec run(map(), keyword()) :: {:ok, map()} | {:error, term(), map()}
  def run(intake, opts \\ []) when is_map(intake) and is_list(opts) do
    jido = Keyword.fetch!(opts, :jido)
    timeout = Keyword.get(opts, :timeout, map_get(intake, :timeout, @default_timeout_ms))
    observer_pid = Keyword.get(opts, :observer_pid) || map_get(intake, :observer_pid)
    debug = Keyword.get(opts, :debug, true)

    case run_pipeline(intake,
           jido: jido,
           timeout: timeout,
           observer_pid: observer_pid,
           debug: debug
         ) do
      {:ok, %{status: :completed} = run} ->
        final = extract_final_production(run.productions)
        {:ok, to_result_map(intake, final, run.productions)}

      {:ok, %{status: :failed} = run} ->
        {:error, {:pipeline_failed, run.failures},
         to_result_map(intake, extract_final_production(run.productions), run.productions)}

      {:error, reason, run} ->
        {:error, reason,
         to_result_map(intake, extract_final_production(run.productions), run.productions)}
    end
  end

  @doc """
  Build intake payload map from issue URL and options.
  """
  @spec build_intake(String.t(), keyword()) :: map()
  def build_intake(issue_url, opts \\ []) when is_binary(issue_url) and is_list(opts) do
    {owner, repo, issue_number} = parse_issue_url(issue_url)
    provider = normalize_provider(Keyword.get(opts, :provider, :claude))
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
  def parse_issue_url(url) when is_binary(url) do
    case Regex.run(~r{github\.com/([^/]+)/([^/]+)/issues/(\d+)}, url) do
      [_, owner, repo, number] -> {owner, repo, String.to_integer(number)}
      _ -> raise ArgumentError, "Invalid GitHub issue URL: #{url}"
    end
  end

  @doc """
  Build a `runic.feed` signal from intake payload.
  """
  @spec intake_signal(map()) :: Jido.Signal.t()
  def intake_signal(payload) when is_map(payload) do
    Jido.Signal.new!("runic.feed", %{data: payload}, source: "/github/pr_bot")
  end

  defp run_pipeline(intake, opts) do
    jido = Keyword.fetch!(opts, :jido)
    timeout = Keyword.fetch!(opts, :timeout)
    debug = Keyword.get(opts, :debug, true)
    observer_pid = Keyword.get(opts, :observer_pid) || map_get(intake, :observer_pid)

    ensure_jido_started!(jido)

    with {:ok, pid} <- Jido.AgentServer.start_link(agent: __MODULE__, jido: jido, debug: debug) do
      try do
        payload = maybe_put_observer(intake, observer_pid)
        Jido.AgentServer.cast(pid, intake_signal(payload))

        completion = Jido.AgentServer.await_completion(pid, timeout: timeout)
        run = snapshot(pid)

        case completion do
          {:ok, %{status: :completed}} ->
            if run.failures == [] do
              {:ok, Map.put(run, :status, :completed)}
            else
              maybe_cleanup_sprite(intake, pid, run.productions)

              {:ok,
               Map.merge(run, %{
                 status: :failed,
                 error: {:pipeline_failed, run.failures},
                 pid: pid
               })}
            end

          {:ok, %{status: :failed}} ->
            maybe_cleanup_sprite(intake, pid, run.productions)
            {:ok, Map.merge(run, %{status: :failed, error: :pipeline_failed, pid: pid})}

          {:error, reason} ->
            maybe_cleanup_sprite(intake, pid, run.productions)
            {:error, reason, Map.merge(run, %{status: :error, error: reason, pid: pid})}
        end
      after
        if Process.alive?(pid), do: GenServer.stop(pid, :normal, 5_000)
      end
    else
      {:error, reason} ->
        {:error, reason, empty_run()}
    end
  end

  defp snapshot(pid) do
    with {:ok, server_state} <- Jido.AgentServer.state(pid),
         strat <- StratState.get(server_state.agent) do
      workflow = strat.workflow

      %{
        productions: Workflow.raw_productions(workflow),
        facts: Workflow.facts(workflow),
        failures: workflow_failures_from_workflow(workflow),
        events: workflow_events(pid),
        result: nil,
        error: nil,
        status: :unknown,
        pid: pid
      }
    else
      _ -> empty_run()
    end
  end

  defp empty_run do
    %{
      productions: [],
      facts: [],
      failures: [],
      events: [],
      result: nil,
      error: nil,
      status: :unknown,
      pid: nil
    }
  end

  defp extract_final_production(productions) do
    case Enum.reverse(productions || []) do
      [last | _] when is_map(last) -> last
      _ -> %{}
    end
  end

  defp to_result_map(intake, final, productions) when is_map(intake) and is_map(final) do
    provider = result_value(final, productions, :provider, map_get(intake, :provider, :claude))

    %{
      status: result_value(final, productions, :status, :completed),
      run_id: result_value(final, productions, :run_id, map_get(intake, :run_id)),
      provider: provider,
      owner: result_value(final, productions, :owner, map_get(intake, :owner)),
      repo: result_value(final, productions, :repo, map_get(intake, :repo)),
      issue_number:
        result_value(final, productions, :issue_number, map_get(intake, :issue_number)),
      issue_url: result_value(final, productions, :issue_url, map_get(intake, :issue_url)),
      base_branch: result_value(final, productions, :base_branch, map_get(intake, :base_branch)),
      branch_name: result_value(final, productions, :branch_name, nil),
      agent_status: result_value(final, productions, :agent_status, nil),
      agent_summary: result_value(final, productions, :agent_summary, nil),
      agent_error: result_value(final, productions, :agent_error, nil),
      claude_status:
        result_value(
          final,
          productions,
          :claude_status,
          if(provider == :claude,
            do: result_value(final, productions, :agent_status, nil),
            else: nil
          )
        ),
      claude_summary:
        result_value(
          final,
          productions,
          :claude_summary,
          if(provider == :claude,
            do: result_value(final, productions, :agent_summary, nil),
            else: nil
          )
        ),
      commit_sha: result_value(final, productions, :commit_sha, nil),
      checks_passed: result_value(final, productions, :checks_passed, nil),
      check_results: result_value(final, productions, :check_results, nil),
      pr_created: result_value(final, productions, :pr_created, nil),
      pr_number: result_value(final, productions, :pr_number, nil),
      pr_url: result_value(final, productions, :pr_url, nil),
      pr_title: result_value(final, productions, :pr_title, nil),
      issue_comment_posted: result_value(final, productions, :issue_comment_posted, nil),
      issue_comment_error: result_value(final, productions, :issue_comment_error, nil),
      sprite_name: result_value(final, productions, :sprite_name, nil),
      session_id: result_value(final, productions, :session_id, nil),
      workspace_dir: result_value(final, productions, :workspace_dir, nil),
      teardown_verified: result_value(final, productions, :teardown_verified, nil),
      teardown_attempts: result_value(final, productions, :teardown_attempts, nil),
      warnings: result_value(final, productions, :warnings, nil),
      message: result_value(final, productions, :message, nil),
      error: result_value(final, productions, :error, nil)
    }
  end

  defp result_value(final, productions, key, default) do
    case map_get(final, key) do
      nil ->
        case production_value(productions, key) do
          nil -> default
          value -> value
        end

      value ->
        value
    end
  end

  defp default_result(intake) do
    %{
      status: :failed,
      run_id: map_get(intake, :run_id),
      provider: map_get(intake, :provider, :claude),
      owner: map_get(intake, :owner),
      repo: map_get(intake, :repo),
      issue_number: map_get(intake, :issue_number),
      issue_url: map_get(intake, :issue_url),
      base_branch: map_get(intake, :base_branch),
      branch_name: nil,
      agent_status: nil,
      agent_summary: nil,
      agent_error: nil,
      claude_status: nil,
      claude_summary: nil,
      commit_sha: nil,
      checks_passed: nil,
      check_results: nil,
      pr_created: nil,
      pr_number: nil,
      pr_url: nil,
      pr_title: nil,
      issue_comment_posted: nil,
      issue_comment_error: nil,
      sprite_name: nil,
      session_id: nil,
      workspace_dir: nil,
      teardown_verified: nil,
      teardown_attempts: nil,
      warnings: nil,
      message: nil,
      error: nil
    }
  end

  defp workflow_events(pid) do
    case Jido.AgentServer.recent_events(pid) do
      {:ok, events} -> events
      _ -> []
    end
  end

  defp workflow_failures_from_workflow(%Workflow{graph: graph}) do
    graph
    |> Graph.vertices()
    |> Enum.flat_map(fn
      %Runic.Workflow.Fact{value: %{status: :failed} = value} -> [value]
      _ -> []
    end)
  rescue
    _ -> []
  end

  defp ensure_jido_started!(jido) when is_atom(jido) do
    case Jido.start(name: jido) do
      {:ok, _pid} ->
        ensure_jido_registry!(jido)

      {:error, {:already_started, _pid}} ->
        ensure_jido_registry!(jido)

      {:error, reason} ->
        raise "Could not start Jido instance #{inspect(jido)}: #{inspect(reason)}"
    end
  end

  defp ensure_jido_started!(_jido),
    do: raise(ArgumentError, ":jido must be an atom instance name")

  defp ensure_jido_registry!(jido) do
    registry = Module.concat(jido, Registry)
    wait_for_registry!(registry, System.monotonic_time(:millisecond) + 2_000)
  end

  defp wait_for_registry!(registry, deadline_ms) do
    case Process.whereis(registry) do
      pid when is_pid(pid) ->
        :ok

      _ ->
        if System.monotonic_time(:millisecond) < deadline_ms do
          Process.sleep(10)
          wait_for_registry!(registry, deadline_ms)
        else
          raise "Jido registry not available: #{inspect(registry)}"
        end
    end
  end

  defp maybe_cleanup_sprite(intake, pid, productions)
       when is_map(intake) and is_list(productions) do
    if map_get(intake, :keep_sprite, false) do
      :ok
    else
      context = cleanup_context(pid, intake, productions)

      case context.session_id do
        session_id when is_binary(session_id) ->
          _ =
            SpriteTeardown.teardown(
              session_id,
              context.sprite_name,
              stop_module(intake),
              context.sprite_config,
              sprites_mod: context.sprites_mod || map_get(intake, :sprites_mod) || Sprites
            )

          :ok

        _ ->
          :ok
      end
    end
  end

  defp cleanup_context(pid, intake, productions) do
    %{
      session_id:
        production_value(productions, :session_id) || session_id_from_workflow_graph(pid),
      sprite_name:
        production_value(productions, :sprite_name) || workflow_last_value(pid, :sprite_name) ||
          "jido-prbot-#{map_get(intake, :run_id, "unknown")}",
      sprite_config:
        production_value(productions, :sprite_config) || workflow_last_value(pid, :sprite_config) ||
          map_get(intake, :sprite_config),
      sprites_mod:
        production_value(productions, :sprites_mod) || workflow_last_value(pid, :sprites_mod) ||
          map_get(intake, :sprites_mod)
    }
  end

  defp production_value(productions, key) when is_list(productions) and is_atom(key) do
    Enum.find_value(Enum.reverse(productions), fn
      value when is_map(value) -> map_get(value, key)
      _ -> nil
    end)
  end

  defp session_id_from_workflow_graph(pid) do
    with {:ok, server_state} <- Jido.AgentServer.state(pid),
         strat <- StratState.get(server_state.agent) do
      strat.workflow
      |> session_ids_from_workflow()
      |> List.last()
    else
      _ -> nil
    end
  end

  defp workflow_last_value(pid, key) when is_atom(key) do
    with {:ok, server_state} <- Jido.AgentServer.state(pid),
         strat <- StratState.get(server_state.agent) do
      strat.workflow
      |> workflow_values_for_key(key)
      |> List.last()
    else
      _ -> nil
    end
  end

  defp workflow_values_for_key(%Workflow{graph: graph}, key) do
    graph
    |> Graph.vertices()
    |> Enum.flat_map(fn
      %Runic.Workflow.Fact{value: value} when is_map(value) ->
        case map_get(value, key) do
          nil -> []
          found -> [found]
        end

      _ ->
        []
    end)
  rescue
    _ -> []
  end

  defp session_ids_from_workflow(%Workflow{graph: graph}) do
    graph
    |> Graph.vertices()
    |> Enum.flat_map(fn
      %Runic.Workflow.Fact{value: value} when is_map(value) ->
        case map_get(value, :session_id) do
          session_id when is_binary(session_id) -> [session_id]
          _ -> []
        end

      _ ->
        []
    end)
  rescue
    _ -> []
  end

  defp stop_module(intake) when is_map(intake) do
    case map_get(intake, :shell_agent_mod) do
      mod when is_atom(mod) -> mod
      _ -> Jido.Shell.Agent
    end
  end

  defp maybe_put_observer(data, pid) when is_map(data) and is_pid(pid),
    do: Map.put(data, :observer_pid, pid)

  defp maybe_put_observer(data, _pid), do: data

  defp ensure_observer(opts) do
    case Keyword.get(opts, :observer_pid) do
      pid when is_pid(pid) ->
        {pid, false}

      _ ->
        case Keyword.get(opts, :observer) do
          shell when is_atom(shell) ->
            if function_exported?(shell, :info, 1) do
              {start_observer(shell), true}
            else
              {nil, false}
            end

          _ ->
            {nil, false}
        end
    end
  end

  defp start_observer(shell), do: spawn_link(fn -> observe_signals(shell, 0) end)

  defp stop_observer(pid) when is_pid(pid) do
    send(pid, :stop)
    :ok
  end

  defp stop_observer(_pid), do: :ok

  defp observe_signals(shell, delta_count) do
    receive do
      :stop ->
        :ok

      {:jido_lib_signal, %Jido.Signal{type: type, data: data}} ->
        next_count = print_signal(shell, type, data, delta_count)
        observe_signals(shell, next_count)
    after
      120_000 ->
        :ok
    end
  end

  defp print_signal(shell, "jido.lib.github.pr_bot.coding_agent.event", data, delta_count) do
    event_type = map_get(data, :event_type, "unknown")
    event = map_get(data, :event, %{})
    next = delta_count + 1

    if rem(next, @delta_log_every) == 0 do
      shell.info("[PrBot][CodingAgent] events=#{next}")
    end

    if event_type in ["stream_event", "content_block_start"] do
      maybe_log_tool_start(shell, event)
    end

    if event_type == "result" do
      shell.info("[PrBot][CodingAgent] result #{result_summary(event)}")
    end

    if event_type == "system" do
      shell.info("[PrBot][CodingAgent] init #{system_summary(event)}")
    end

    next
  end

  defp print_signal(shell, type, data, delta_count) do
    cond do
      String.starts_with?(type, "jido.lib.github.pr_bot.coding_agent.") ->
        print_coding_agent_signal(shell, type, data)
        delta_count

      String.starts_with?(type, "jido.lib.github.pr_bot.claude.") ->
        print_legacy_claude_signal(shell, type, data)
        delta_count

      String.starts_with?(type, "jido.lib.github.issue_triage.delegate.") ->
        print_delegate_signal(shell, type, data)
        delta_count

      type == "jido.lib.github.issue_triage.validate_runtime.checked" ->
        shell.info("[PrBot][Runtime] #{runtime_summary(data)}")
        delta_count

      true ->
        delta_count
    end
  end

  defp print_coding_agent_signal(shell, "jido.lib.github.pr_bot.coding_agent.started", data) do
    provider = map_get(data, :provider, "unknown")

    shell.info(
      "[PrBot][CodingAgent] provider=#{provider} started issue=#{map_get(data, :issue_number, "?")}"
    )
  end

  defp print_coding_agent_signal(shell, "jido.lib.github.pr_bot.coding_agent.mode", data) do
    provider = map_get(data, :provider, "unknown")

    shell.info(
      "[PrBot][CodingAgent] provider=#{provider} mode=#{map_get(data, :mode, "unknown")}"
    )
  end

  defp print_coding_agent_signal(shell, "jido.lib.github.pr_bot.coding_agent.heartbeat", data) do
    shell.info("[PrBot][CodingAgent] heartbeat idle_ms=#{map_get(data, :idle_ms, 0)}")
  end

  defp print_coding_agent_signal(shell, "jido.lib.github.pr_bot.coding_agent.completed", data) do
    shell.info(
      "[PrBot][CodingAgent] completed events=#{map_get(data, :event_count, 0)} bytes=#{map_get(data, :summary_bytes, 0)}"
    )
  end

  defp print_coding_agent_signal(shell, "jido.lib.github.pr_bot.coding_agent.failed", data) do
    shell.info("[PrBot][CodingAgent] failed error=#{map_get(data, :error, "unknown")}")
  end

  defp print_coding_agent_signal(shell, "jido.lib.github.pr_bot.coding_agent.raw_line", data) do
    shell.info("[PrBot][CodingAgent][raw] #{map_get(data, :line, "")}")
  end

  defp print_coding_agent_signal(_shell, _type, _data), do: :ok

  defp print_legacy_claude_signal(shell, type, data) do
    translated =
      type
      |> String.replace_prefix(
        "jido.lib.github.pr_bot.claude.",
        "jido.lib.github.pr_bot.coding_agent."
      )

    print_coding_agent_signal(shell, translated, data)
  end

  defp print_delegate_signal(shell, type, data) do
    suffix = String.replace_prefix(type, "jido.lib.github.issue_triage.delegate.", "")
    node = map_get(data, :node, "unknown")
    tag = map_get(data, :tag, "unknown")
    shell.info("[PrBot][Delegate] #{suffix} node=#{node} tag=#{tag}")
  end

  defp runtime_summary(data) do
    checks = map_get(data, :runtime_checks, %{})
    shared = map_get(checks, :shared, checks)
    provider_checks = map_get(checks, :provider, %{})
    provider_name = map_get(checks, :provider_name, map_get(data, :provider, "unknown"))
    tools = map_get(provider_checks, :tools, %{})
    probes = map_get(provider_checks, :probes, [])

    tools_ok =
      case tools do
        map when is_map(map) -> Enum.all?(map, fn {_tool, present?} -> present? == true end)
        _ -> false
      end

    probes_ok =
      case probes do
        list when is_list(list) -> Enum.all?(list, &(map_get(&1, :pass?, false) == true))
        _ -> false
      end

    "gh=#{map_get(shared, :gh, false)} git=#{map_get(shared, :git, false)} token=#{map_get(shared, :github_token_visible, false)} auth=#{map_get(shared, :gh_auth, false)} provider=#{provider_name} tools_ok=#{tools_ok} probes_ok=#{probes_ok}"
  end

  defp maybe_log_tool_start(shell, event) when is_map(event) do
    with %{"event" => %{"content_block" => %{"name" => name}}} <- event do
      shell.info("[PrBot][CodingAgent] tool=#{name}")
    else
      _ -> :ok
    end
  end

  defp maybe_log_tool_start(_shell, _event), do: :ok

  defp result_summary(event) when is_map(event) do
    duration_ms = map_get(event, :duration_ms, 0)
    turns = map_get(event, :num_turns, 0)
    cost = map_get(event, :total_cost_usd, 0)
    status = map_get(event, :subtype, "unknown")
    "status=#{status} turns=#{turns} duration_ms=#{duration_ms} cost_usd=#{cost}"
  end

  defp result_summary(_event), do: "status=unknown"

  defp system_summary(event) when is_map(event) do
    model = map_get(event, :model, "unknown")
    version = map_get(event, :claude_code_version, "unknown")
    "model=#{model} cli=#{version}"
  end

  defp system_summary(_event), do: "model=unknown"

  defp normalize_provider(provider) when provider in @supported_providers, do: provider

  defp normalize_provider(provider) when is_binary(provider) do
    provider
    |> String.trim()
    |> String.downcase()
    |> case do
      "claude" -> :claude
      "amp" -> :amp
      "codex" -> :codex
      "gemini" -> :gemini
      _ -> :claude
    end
  end

  defp normalize_provider(_), do: :claude

  defp map_get(map, key, default \\ nil) when is_map(map) and is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key), default)
    end
  end

  defp generate_run_id do
    :crypto.strong_rand_bytes(6)
    |> Base.encode16(case: :lower)
  end

  defp normalize_run_id(run_id) when is_binary(run_id) do
    if String.trim(run_id) == "", do: generate_run_id(), else: run_id
  end

  defp normalize_run_id(_), do: generate_run_id()
end
