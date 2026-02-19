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
    strategy:
      {Jido.Runic.Strategy,
       workflow_fn: &__MODULE__.build_workflow/0,
       child_modules: %{claude_sprite: Jido.Lib.Github.Agents.ClaudeSpriteAgent}},
    schema: []

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.Lib.Github.Actions.IssueTriage
  alias Jido.Lib.Github.Actions.IssueTriage.ValidateHostEnv
  alias Jido.Lib.Github.Actions.PrBot, as: PrActions
  alias Jido.Lib.Github.IssueTriage.SpriteTeardown
  alias Jido.Runic.ActionNode
  alias Runic.Workflow

  @default_timeout_ms 900_000
  @await_buffer_ms 60_000
  @default_check_commands ["mix test --exclude integration"]
  @delta_log_every 200

  @doc false
  @spec plugin_specs() :: [Jido.Plugin.Spec.t()]
  def plugin_specs, do: []

  @doc """
  Build the PR workflow graph with delegated Claude coding.
  """
  @spec build_workflow() :: Workflow.t()
  def build_workflow do
    claude_node =
      ActionNode.new(PrActions.ClaudeCode, %{},
        name: :claude_code,
        executor: {:child, :claude_sprite},
        exec_opts: [max_retries: 0]
      )

    Workflow.new(name: :github_pr_bot)
    |> Workflow.add(IssueTriage.ValidateHostEnv)
    |> Workflow.add(IssueTriage.ProvisionSprite, to: :validate_host_env)
    |> Workflow.add(IssueTriage.PrepareGithubAuth, to: :provision_sprite)
    |> Workflow.add(IssueTriage.FetchIssue, to: :prepare_github_auth)
    |> Workflow.add(IssueTriage.CloneRepo, to: :fetch_issue)
    |> Workflow.add(IssueTriage.SetupRepo, to: :clone_repo)
    |> Workflow.add(IssueTriage.ValidateRuntime, to: :setup_repo)
    |> Workflow.add(PrActions.EnsureBranch, to: :validate_runtime)
    |> Workflow.add(claude_node, to: :ensure_branch)
    |> Workflow.add(PrActions.EnsureCommit, to: :claude_code)
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
            env: ValidateHostEnv.build_sprite_env()
          }
      end

    %{
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
    %{
      status: result_value(final, productions, :status, :completed),
      run_id: result_value(final, productions, :run_id, map_get(intake, :run_id)),
      owner: result_value(final, productions, :owner, map_get(intake, :owner)),
      repo: result_value(final, productions, :repo, map_get(intake, :repo)),
      issue_number:
        result_value(final, productions, :issue_number, map_get(intake, :issue_number)),
      issue_url: result_value(final, productions, :issue_url, map_get(intake, :issue_url)),
      base_branch: result_value(final, productions, :base_branch, map_get(intake, :base_branch)),
      branch_name: result_value(final, productions, :branch_name, nil),
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
      owner: map_get(intake, :owner),
      repo: map_get(intake, :repo),
      issue_number: map_get(intake, :issue_number),
      issue_url: map_get(intake, :issue_url),
      base_branch: map_get(intake, :base_branch),
      branch_name: nil,
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

  defp print_signal(shell, "jido.lib.github.pr_bot.claude.event", data, delta_count) do
    event_kind = map_get(data, :event_kind, "unknown")
    event = map_get(data, :event, %{})

    case event_kind do
      "stream:content_block_delta" ->
        next = delta_count + 1

        if rem(next, @delta_log_every) == 0 do
          shell.info("[PrBot][Claude] deltas=#{next}")
        end

        next

      "stream:content_block_start" ->
        maybe_log_tool_start(shell, event)
        delta_count

      "result" ->
        shell.info("[PrBot][Claude] result #{result_summary(event)}")
        delta_count

      "system" ->
        shell.info("[PrBot][Claude] init #{system_summary(event)}")
        delta_count

      _ ->
        delta_count
    end
  end

  defp print_signal(shell, type, data, delta_count) do
    cond do
      String.starts_with?(type, "jido.lib.github.pr_bot.claude.") ->
        print_claude_signal(shell, type, data)
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

  defp print_claude_signal(shell, "jido.lib.github.pr_bot.claude.started", data) do
    shell.info("[PrBot][Claude] started issue=#{map_get(data, :issue_number, "?")}")
  end

  defp print_claude_signal(shell, "jido.lib.github.pr_bot.claude.mode", data) do
    shell.info("[PrBot][Claude] mode=#{map_get(data, :mode, "unknown")}")
  end

  defp print_claude_signal(shell, "jido.lib.github.pr_bot.claude.heartbeat", data) do
    shell.info("[PrBot][Claude] heartbeat idle_ms=#{map_get(data, :idle_ms, 0)}")
  end

  defp print_claude_signal(shell, "jido.lib.github.pr_bot.claude.completed", data) do
    shell.info(
      "[PrBot][Claude] completed events=#{map_get(data, :event_count, 0)} bytes=#{map_get(data, :summary_bytes, 0)}"
    )
  end

  defp print_claude_signal(shell, "jido.lib.github.pr_bot.claude.failed", data) do
    shell.info("[PrBot][Claude] failed error=#{map_get(data, :error, "unknown")}")
  end

  defp print_claude_signal(shell, "jido.lib.github.pr_bot.claude.raw_line", data) do
    shell.info("[PrBot][Claude][raw] #{map_get(data, :line, "")}")
  end

  defp print_claude_signal(_shell, _type, _data), do: :ok

  defp print_delegate_signal(shell, type, data) do
    suffix = String.replace_prefix(type, "jido.lib.github.issue_triage.delegate.", "")
    node = map_get(data, :node, "unknown")
    tag = map_get(data, :tag, "unknown")
    shell.info("[PrBot][Delegate] #{suffix} node=#{node} tag=#{tag}")
  end

  defp runtime_summary(data) do
    checks = map_get(data, :runtime_checks, %{})

    "gh=#{map_get(checks, :gh, false)} git=#{map_get(checks, :git, false)} claude=#{map_get(checks, :claude, false)}"
  end

  defp maybe_log_tool_start(shell, event) when is_map(event) do
    with %{"event" => %{"content_block" => %{"name" => name}}} <- event do
      shell.info("[PrBot][Claude] tool=#{name}")
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
