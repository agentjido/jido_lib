defmodule Jido.Lib.Github.Agents.IssueTriageBot do
  @moduledoc """
  Canonical GitHub issue triage bot.

  This module is both:
  - the Runic orchestrator agent definition, and
  - the public intake/run API (`triage/2`, `run/2`).
  """

  use Jido.Agent,
    name: "github_issue_triage_bot",
    strategy:
      {Jido.Runic.Strategy,
       workflow_fn: &__MODULE__.build_workflow/0,
       child_modules: %{
         claude_sprite: Jido.Lib.Github.Agents.ClaudeSpriteAgent
       }},
    schema: []

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.Lib.Github.Actions.IssueTriage
  alias Jido.Lib.Github.Actions.IssueTriage.ValidateHostEnv
  alias Jido.Lib.Github.IssueTriage.SpriteTeardown
  alias Jido.Lib.Github.Schema.IssueTriage.Result
  alias Jido.Runic.ActionNode
  alias Runic.Workflow

  @default_timeout_ms 300_000
  @await_buffer_ms 60_000
  @delta_log_every 200

  @type triage_response :: %{
          issue_url: String.t(),
          intake: map(),
          status: :completed | :failed | :error,
          result: Result.t() | nil,
          error: term() | nil,
          productions: [map()],
          facts: [Runic.Workflow.Fact.t()],
          events: [map()],
          failures: [map()],
          pid: pid() | nil
        }

  @doc false
  @spec plugin_specs() :: [Jido.Plugin.Spec.t()]
  def plugin_specs, do: []

  @doc "Build the sprite triage DAG with delegated Claude execution."
  @spec build_workflow() :: Workflow.t()
  def build_workflow do
    claude_node =
      ActionNode.new(IssueTriage.Claude, %{},
        name: :claude,
        executor: {:child, :claude_sprite},
        exec_opts: [max_retries: 0]
      )

    Workflow.new(name: :github_issue_triage_bot)
    |> Workflow.add(IssueTriage.ValidateHostEnv)
    |> Workflow.add(IssueTriage.ProvisionSprite, to: :validate_host_env)
    |> Workflow.add(IssueTriage.PrepareGithubAuth, to: :provision_sprite)
    |> Workflow.add(IssueTriage.FetchIssue, to: :prepare_github_auth)
    |> Workflow.add(IssueTriage.CloneRepo, to: :fetch_issue)
    |> Workflow.add(IssueTriage.SetupRepo, to: :clone_repo)
    |> Workflow.add(IssueTriage.ValidateRuntime, to: :setup_repo)
    |> Workflow.add(claude_node, to: :validate_runtime)
    |> Workflow.add(IssueTriage.CommentIssue, to: :claude)
    |> Workflow.add(IssueTriage.TeardownSprite, to: :comment_issue)
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

    {observer_pid, owns_observer?} = ensure_observer(opts)

    try do
      case run_pipeline(intake,
             jido: jido,
             timeout: await_timeout,
             observer_pid: observer_pid,
             debug: debug
           ) do
        {:ok, %{status: :completed, result: result} = run} ->
          response(issue_url, intake, :completed, result, nil, run)

        {:ok, %{status: :failed, error: error} = run} ->
          response(issue_url, intake, :failed, nil, error, run)

        {:error, reason, run} ->
          response(issue_url, intake, :error, nil, reason, run)
      end
    after
      if owns_observer?, do: stop_observer(observer_pid)
    end
  end

  @doc """
  Run triage from an already-built intake map.
  """
  @spec run(map() | struct(), keyword()) :: {:ok, Result.t()} | {:error, term()}
  def run(intake, opts \\ [])

  def run(%{__struct__: _} = intake, opts), do: run(Map.from_struct(intake), opts)

  def run(intake, opts) when is_map(intake) do
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
      {:ok, %{status: :completed, result: result}} ->
        {:ok, result}

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
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)
    run_id = normalize_run_id(Keyword.get(opts, :run_id))
    setup_commands = Keyword.get(opts, :setup_commands, Keyword.get(opts, :setup_cmd, []))

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
            run_completed(intake, pid, run)

          {:ok, %{status: :failed}} ->
            maybe_cleanup_sprite(intake, pid, run.productions)

            {:ok,
             Map.merge(run, %{status: :failed, result: nil, error: :pipeline_failed, pid: pid})}

          {:error, reason} ->
            maybe_cleanup_sprite(intake, pid, run.productions)

            {:error, reason,
             Map.merge(run, %{status: :error, result: nil, error: reason, pid: pid})}
        end
      after
        if Process.alive?(pid), do: GenServer.stop(pid, :normal, 5_000)
      end
    else
      {:error, reason} ->
        {:error, reason, empty_run()}
    end
  end

  defp run_completed(intake, pid, run) do
    if run.failures == [] do
      final = extract_final_production(run.productions)
      result = Result.new!(to_result_attrs(intake, final))
      {:ok, Map.merge(run, %{status: :completed, result: result, error: nil, pid: pid})}
    else
      maybe_cleanup_sprite(intake, pid, run.productions)

      {:ok,
       Map.merge(run, %{
         status: :failed,
         result: nil,
         error: {:pipeline_failed, run.failures},
         pid: pid
       })}
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

  defp response(issue_url, intake, status, result, error, run) do
    %{
      issue_url: issue_url,
      intake: intake,
      status: status,
      result: result,
      error: error,
      productions: run.productions || [],
      facts: run.facts || [],
      events: run.events || [],
      failures: run.failures || [],
      pid: run.pid
    }
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

  defp maybe_put_observer(data, pid) when is_map(data) and is_pid(pid),
    do: Map.put(data, :observer_pid, pid)

  defp maybe_put_observer(data, _pid), do: data

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

  defp extract_final_production(productions) do
    Enum.find(productions, List.last(productions) || %{}, fn production ->
      is_map(production) and Map.has_key?(production, :message)
    end)
  end

  defp to_result_attrs(intake, final) do
    %{
      status: final[:status] || :completed,
      run_id: final[:run_id] || map_get(intake, :run_id),
      owner: final[:owner] || map_get(intake, :owner),
      repo: final[:repo] || map_get(intake, :repo),
      issue_number: final[:issue_number] || map_get(intake, :issue_number),
      message: final[:message],
      investigation: final[:investigation],
      investigation_status: final[:investigation_status],
      investigation_error: final[:investigation_error],
      comment_posted: final[:comment_posted],
      comment_url: final[:comment_url],
      comment_error: final[:comment_error],
      sprite_name: final[:sprite_name],
      session_id: final[:session_id],
      workspace_dir: final[:workspace_dir],
      teardown_verified: final[:teardown_verified],
      teardown_attempts: final[:teardown_attempts],
      warnings: final[:warnings],
      runtime_checks: final[:runtime_checks]
    }
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
          "jido-triage-#{map_get(intake, :run_id, "unknown")}",
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
      value when is_map(value) ->
        map_get(value, key)

      _ ->
        nil
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

  defp print_signal(shell, "jido.lib.github.issue_triage.claude_probe.event", data, delta_count) do
    event = map_get(data, :event, %{})
    kind = map_get(data, :event_kind, "unknown")

    case kind do
      "stream:content_block_delta" ->
        next = delta_count + 1

        if rem(next, @delta_log_every) == 0 do
          shell.info("[Claude] content deltas=#{next}")
        end

        next

      "stream:content_block_start" ->
        maybe_log_tool_start(shell, event)
        delta_count

      "result" ->
        shell.info("[Claude] result #{result_summary(event)}")
        delta_count

      "system" ->
        shell.info("[Claude] init #{system_summary(event)}")
        delta_count

      _ ->
        delta_count
    end
  end

  defp print_signal(shell, type, data, delta_count) do
    cond do
      String.starts_with?(type, "jido.lib.github.issue_triage.claude_probe.") ->
        print_claude_signal(shell, type, data)
        delta_count

      String.starts_with?(type, "jido.lib.github.issue_triage.delegate.") ->
        print_delegate_signal(shell, type, data)
        delta_count

      type == "jido.lib.github.issue_triage.validate_runtime.checked" ->
        shell.info("[Runtime] #{runtime_summary(data)}")
        delta_count

      true ->
        delta_count
    end
  end

  defp print_claude_signal(shell, "jido.lib.github.issue_triage.claude_probe.started", data) do
    shell.info("[Claude] started #{claude_signal_context(data)}")
  end

  defp print_claude_signal(shell, "jido.lib.github.issue_triage.claude_probe.mode", data) do
    mode = map_get(data, :mode, "unknown")
    shell.info("[Claude] mode=#{mode}")
  end

  defp print_claude_signal(shell, "jido.lib.github.issue_triage.claude_probe.heartbeat", data) do
    idle_ms = map_get(data, :idle_ms, 0)
    shell.info("[Claude] heartbeat idle_ms=#{idle_ms}")
  end

  defp print_claude_signal(shell, "jido.lib.github.issue_triage.claude_probe.completed", data) do
    events = map_get(data, :event_count, 0)
    bytes = map_get(data, :investigation_bytes, 0)
    shell.info("[Claude] completed events=#{events} bytes=#{bytes}")
  end

  defp print_claude_signal(shell, "jido.lib.github.issue_triage.claude_probe.failed", data) do
    error = map_get(data, :error, "unknown")
    shell.info("[Claude] failed error=#{error}")
  end

  defp print_claude_signal(shell, "jido.lib.github.issue_triage.claude_probe.raw_line", data) do
    shell.info("[Claude][raw] #{map_get(data, :line, "")}")
  end

  defp print_claude_signal(_shell, "jido.lib.github.issue_triage.claude_probe.event", _data),
    do: :ok

  defp print_claude_signal(_shell, _type, _data), do: :ok

  defp print_delegate_signal(shell, type, data) do
    suffix = String.replace_prefix(type, "jido.lib.github.issue_triage.delegate.", "")
    status = map_get(data, :status, suffix)
    node = map_get(data, :node, "unknown")
    tag = map_get(data, :tag, "unknown")
    shell.info("[Delegate] #{status} node=#{node} tag=#{tag}")
  end

  defp runtime_summary(data) do
    checks = map_get(data, :runtime_checks, %{})
    gh = map_get(checks, :gh, false)
    git = map_get(checks, :git, false)
    claude = map_get(checks, :claude, false)
    base = map_get(checks, :base_url_present, false)
    auth = map_get(checks, :auth_source, "unknown")
    "gh=#{gh} git=#{git} claude=#{claude} base_url=#{base} auth=#{auth}"
  end

  defp claude_signal_context(data) do
    issue_number = map_get(data, :issue_number, "?")
    session_id = map_get(data, :session_id, "")
    "issue=#{issue_number} session=#{session_id}"
  end

  defp maybe_log_tool_start(shell, event) when is_map(event) do
    with %{"event" => %{"content_block" => %{"name" => name}}} <- event do
      shell.info("[Claude] tool=#{name}")
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
