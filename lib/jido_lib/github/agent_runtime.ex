defmodule Jido.Lib.Github.AgentRuntime do
  @moduledoc false

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.Lib.Github.Helpers
  alias Runic.Workflow

  @delta_log_every 200

  @type run_snapshot :: %{
          productions: [map()],
          facts: [Runic.Workflow.Fact.t()],
          failures: [map()],
          events: [map()],
          result: map() | nil,
          error: term() | nil,
          status: atom(),
          pid: pid() | nil
        }

  @spec run_pipeline(module(), map(), keyword()) ::
          {:ok, run_snapshot()} | {:error, term(), run_snapshot()}
  def run_pipeline(agent_module, intake, opts)
      when is_atom(agent_module) and is_map(intake) and is_list(opts) do
    timeout = Keyword.fetch!(opts, :timeout)
    debug = Keyword.get(opts, :debug, true)
    jido = Keyword.fetch!(opts, :jido)
    observer_pid = Keyword.get(opts, :observer_pid) || Helpers.map_get(intake, :observer_pid)
    sprite_prefix = Keyword.get(opts, :sprite_prefix, "jido-triage")

    pipeline_meta =
      telemetry_meta(intake)
      |> Map.merge(%{agent: agent_module})

    action_handler_id = "jido-lib-github-action-forward-#{System.unique_integer([:positive])}"

    attach_action_forwarder(action_handler_id, pipeline_meta)

    :telemetry.execute(
      [:jido_lib, :github, :pipeline, :start],
      %{system_time: System.system_time()},
      pipeline_meta
    )

    result =
      with :ok <- ensure_jido_ready(jido),
           {:ok, pid} <-
             Jido.AgentServer.start_link(agent: agent_module, jido: jido, debug: debug) do
        try do
          payload = maybe_put_observer(intake, observer_pid)
          Jido.AgentServer.cast(pid, agent_module.intake_signal(payload))

          completion = Jido.AgentServer.await_completion(pid, timeout: timeout)
          run = snapshot(pid)

          case completion do
            {:ok, %{status: :completed}} ->
              if run.failures == [] do
                {:ok, Map.merge(run, %{status: :completed, error: nil, pid: pid})}
              else
                maybe_cleanup_sprite(intake, pid, run.productions, sprite_prefix)

                {:ok,
                 Map.merge(run, %{
                   status: :failed,
                   result: nil,
                   error: {:pipeline_failed, run.failures},
                   pid: pid
                 })}
              end

            {:ok, %{status: :failed}} ->
              maybe_cleanup_sprite(intake, pid, run.productions, sprite_prefix)

              {:ok,
               Map.merge(run, %{status: :failed, result: nil, error: :pipeline_failed, pid: pid})}

            {:error, reason} ->
              maybe_cleanup_sprite(intake, pid, run.productions, sprite_prefix)

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

    case result do
      {:ok, run} ->
        :telemetry.execute(
          [:jido_lib, :github, :pipeline, :stop],
          %{system_time: System.system_time()},
          Map.merge(pipeline_meta, %{status: run.status, error: inspect(run.error)})
        )

      {:error, reason, run} ->
        :telemetry.execute(
          [:jido_lib, :github, :pipeline, :exception],
          %{system_time: System.system_time()},
          Map.merge(pipeline_meta, %{status: run.status, error: inspect(reason)})
        )
    end

    detach_action_forwarder(action_handler_id)
    result
  end

  @spec ensure_observer(keyword(), String.t()) :: {pid() | nil, boolean()}
  def ensure_observer(opts, label) when is_list(opts) and is_binary(label) do
    case Keyword.get(opts, :observer_pid) do
      pid when is_pid(pid) ->
        {pid, false}

      _ ->
        case Keyword.get(opts, :observer) do
          shell when is_atom(shell) ->
            if function_exported?(shell, :info, 1) do
              {start_observer(shell, label), true}
            else
              {nil, false}
            end

          _ ->
            {nil, false}
        end
    end
  end

  @spec stop_observer(pid() | nil) :: :ok
  def stop_observer(pid) when is_pid(pid) do
    send(pid, :stop)
    :ok
  end

  def stop_observer(_), do: :ok

  @spec maybe_put_observer(map(), pid() | nil) :: map()
  def maybe_put_observer(data, pid) when is_map(data) and is_pid(pid),
    do: Map.put(data, :observer_pid, pid)

  def maybe_put_observer(data, _), do: data

  @spec snapshot(pid()) :: run_snapshot()
  def snapshot(pid) when is_pid(pid) do
    with {:ok, server_state} <- Jido.AgentServer.state(pid),
         strat <- StratState.get(server_state.agent) do
      workflow = strat.workflow

      %{
        productions: Workflow.raw_productions(workflow),
        facts: Workflow.facts(workflow),
        failures: workflow_failures(workflow),
        events: workflow_events(pid),
        result: nil,
        error: nil,
        status: :unknown,
        pid: pid
      }
    else
      _ ->
        empty_run()
    end
  end

  @spec empty_run() :: run_snapshot()
  def empty_run do
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

  @spec extract_final_production([map()]) :: map()
  def extract_final_production(productions) when is_list(productions) do
    case Enum.reverse(productions) do
      [last | _] when is_map(last) -> last
      _ -> %{}
    end
  end

  @spec workflow_events(pid()) :: [map()]
  def workflow_events(pid) when is_pid(pid) do
    case Jido.AgentServer.recent_events(pid) do
      {:ok, events} -> events
      _ -> []
    end
  end

  @spec workflow_failures(Workflow.t()) :: [map()]
  def workflow_failures(%Workflow{graph: graph}) do
    graph
    |> Graph.vertices()
    |> Enum.flat_map(fn
      %Runic.Workflow.Fact{value: %{status: :failed} = value} -> [value]
      _ -> []
    end)
  rescue
    _ -> []
  end

  defp ensure_jido_ready(jido) when is_atom(jido) do
    registry = Module.concat(jido, Registry)

    case Process.whereis(registry) do
      pid when is_pid(pid) -> :ok
      _ -> {:error, {:jido_not_started, jido}}
    end
  end

  defp ensure_jido_ready(other), do: {:error, {:invalid_jido_instance, other}}

  defp maybe_cleanup_sprite(intake, pid, productions, sprite_prefix)
       when is_map(intake) and is_list(productions) and is_binary(sprite_prefix) do
    if Helpers.map_get(intake, :keep_sprite, false) do
      :ok
    else
      context = cleanup_context(pid, intake, productions, sprite_prefix)

      case context.session_id do
        session_id when is_binary(session_id) ->
          _ =
            Helpers.teardown_sprite(
              session_id,
              context.sprite_name,
              stop_module(intake),
              context.sprite_config,
              sprites_mod: context.sprites_mod || Helpers.map_get(intake, :sprites_mod) || Sprites
            )

          :ok

        _ ->
          :ok
      end
    end
  end

  defp cleanup_context(pid, intake, productions, sprite_prefix) do
    %{
      session_id:
        production_value(productions, :session_id) || session_id_from_workflow_graph(pid),
      sprite_name:
        production_value(productions, :sprite_name) || workflow_last_value(pid, :sprite_name) ||
          "#{sprite_prefix}-#{Helpers.map_get(intake, :run_id, "unknown")}",
      sprite_config:
        production_value(productions, :sprite_config) || workflow_last_value(pid, :sprite_config) ||
          Helpers.map_get(intake, :sprite_config),
      sprites_mod:
        production_value(productions, :sprites_mod) || workflow_last_value(pid, :sprites_mod) ||
          Helpers.map_get(intake, :sprites_mod)
    }
  end

  defp stop_module(intake) when is_map(intake) do
    case Helpers.map_get(intake, :shell_agent_mod) do
      mod when is_atom(mod) -> mod
      _ -> Jido.Shell.Agent
    end
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
        case Helpers.map_get(value, key) do
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
        case Helpers.map_get(value, :session_id) do
          session_id when is_binary(session_id) -> [session_id]
          _ -> []
        end

      _ ->
        []
    end)
  rescue
    _ -> []
  end

  defp production_value(productions, key) when is_list(productions) and is_atom(key) do
    Enum.find_value(Enum.reverse(productions), fn
      value when is_map(value) -> Helpers.map_get(value, key)
      _ -> nil
    end)
  end

  defp start_observer(shell, label), do: spawn_link(fn -> observe_signals(shell, label, 0) end)

  defp observe_signals(shell, label, delta_count) do
    receive do
      :stop ->
        :ok

      {:jido_lib_signal, %Jido.Signal{type: type, data: data}} ->
        next_count = print_signal(shell, label, type, data, delta_count)
        observe_signals(shell, label, next_count)
    after
      120_000 ->
        :ok
    end
  end

  defp print_signal(shell, label, "jido.lib.github.coding_agent.event", data, delta_count) do
    event = Helpers.map_get(data, :event, %{})
    event_type = Helpers.map_get(data, :event_type, Helpers.map_get(event, :type, "unknown"))
    next = delta_count + 1

    if rem(next, @delta_log_every) == 0 do
      shell.info("[#{label}][CodingAgent] events=#{next}")
    end

    if event_type in ["stream_event", "content_block_start"] do
      maybe_log_tool_start(shell, label, event)
    end

    if event_type == "result" do
      shell.info("[#{label}][CodingAgent] result #{result_summary(event)}")
    end

    if event_type == "system" do
      shell.info("[#{label}][CodingAgent] init #{system_summary(event)}")
    end

    next
  end

  defp print_signal(shell, label, type, data, delta_count) do
    cond do
      String.starts_with?(type, "jido.lib.github.coding_agent.") ->
        print_coding_agent_signal(shell, label, type, data)
        delta_count

      type == "jido.lib.github.validate_runtime.checked" ->
        shell.info("[#{label}][Runtime] #{runtime_summary(data)}")
        delta_count

      true ->
        delta_count
    end
  end

  defp print_coding_agent_signal(shell, label, "jido.lib.github.coding_agent.started", data) do
    provider = Helpers.map_get(data, :provider, "unknown")
    issue_number = Helpers.map_get(data, :issue_number, "?")
    shell.info("[#{label}][CodingAgent] provider=#{provider} started issue=#{issue_number}")
  end

  defp print_coding_agent_signal(shell, label, "jido.lib.github.coding_agent.mode", data) do
    provider = Helpers.map_get(data, :provider, "unknown")
    mode = Helpers.map_get(data, :mode, "unknown")
    shell.info("[#{label}][CodingAgent] provider=#{provider} mode=#{mode}")
  end

  defp print_coding_agent_signal(shell, label, "jido.lib.github.coding_agent.heartbeat", data) do
    shell.info("[#{label}][CodingAgent] heartbeat idle_ms=#{Helpers.map_get(data, :idle_ms, 0)}")
  end

  defp print_coding_agent_signal(shell, label, "jido.lib.github.coding_agent.completed", data) do
    events = Helpers.map_get(data, :event_count, 0)
    bytes = Helpers.map_get(data, :summary_bytes, 0)
    shell.info("[#{label}][CodingAgent] completed events=#{events} bytes=#{bytes}")
  end

  defp print_coding_agent_signal(shell, label, "jido.lib.github.coding_agent.failed", data) do
    error = Helpers.map_get(data, :error, "unknown")
    shell.info("[#{label}][CodingAgent] failed error=#{error}")
  end

  defp print_coding_agent_signal(shell, label, "jido.lib.github.coding_agent.raw_line", data) do
    line = Helpers.map_get(data, :line, "")
    shell.info("[#{label}][CodingAgent][raw] #{line}")
  end

  defp print_coding_agent_signal(_shell, _label, _type, _data), do: :ok

  defp runtime_summary(data) do
    checks = Helpers.map_get(data, :runtime_checks, %{})
    shared = Helpers.map_get(checks, :shared, checks)
    provider_checks = Helpers.map_get(checks, :provider, %{})

    provider_name =
      Helpers.map_get(checks, :provider_name, Helpers.map_get(data, :provider, "unknown"))

    tools = Helpers.map_get(provider_checks, :tools, %{})
    probes = Helpers.map_get(provider_checks, :probes, [])

    tools_ok =
      case tools do
        map when is_map(map) -> Enum.all?(map, fn {_tool, present?} -> present? == true end)
        _ -> false
      end

    probes_ok =
      case probes do
        list when is_list(list) -> Enum.all?(list, &(Helpers.map_get(&1, :pass?, false) == true))
        _ -> false
      end

    "gh=#{Helpers.map_get(shared, :gh, false)} git=#{Helpers.map_get(shared, :git, false)} token=#{Helpers.map_get(shared, :github_token_visible, false)} auth=#{Helpers.map_get(shared, :gh_auth, false)} provider=#{provider_name} tools_ok=#{tools_ok} probes_ok=#{probes_ok}"
  end

  defp maybe_log_tool_start(shell, label, event) when is_map(event) do
    with %{"event" => %{"content_block" => %{"name" => name}}} <- event do
      shell.info("[#{label}][CodingAgent] tool=#{name}")
    else
      _ -> :ok
    end
  end

  defp maybe_log_tool_start(_shell, _label, _event), do: :ok

  defp result_summary(event) when is_map(event) do
    duration_ms = Helpers.map_get(event, :duration_ms, 0)
    turns = Helpers.map_get(event, :num_turns, 0)
    cost = Helpers.map_get(event, :total_cost_usd, 0)
    status = Helpers.map_get(event, :subtype, "unknown")
    "status=#{status} turns=#{turns} duration_ms=#{duration_ms} cost_usd=#{cost}"
  end

  defp result_summary(_event), do: "status=unknown"

  defp system_summary(event) when is_map(event) do
    model = Helpers.map_get(event, :model, "unknown")
    version = Helpers.map_get(event, :claude_code_version, "unknown")
    "model=#{model} cli=#{version}"
  end

  defp system_summary(_event), do: "model=unknown"

  defp attach_action_forwarder(handler_id, base_meta) do
    _ = :telemetry.detach(handler_id)

    :telemetry.attach_many(
      handler_id,
      [
        [:jido_runic, :runnable, :started],
        [:jido_runic, :runnable, :completed],
        [:jido_runic, :runnable, :failed]
      ],
      &__MODULE__.forward_action_telemetry/4,
      %{base_meta: base_meta}
    )
  rescue
    _ -> :ok
  end

  defp detach_action_forwarder(handler_id) do
    :telemetry.detach(handler_id)
  rescue
    _ -> :ok
  end

  @doc false
  def forward_action_telemetry([:jido_runic, :runnable, status], measurements, metadata, config) do
    base_meta = config[:base_meta] || %{}

    node_name =
      case metadata[:node] do
        %{name: name} -> name
        _ -> :unknown
      end

    event_meta =
      Map.merge(base_meta, %{
        node: node_name,
        attempt: Helpers.map_get(metadata, :attempt, 0),
        status: status,
        error: Helpers.map_get(metadata, :error)
      })

    duration_ms = duration_ms(measurements)

    case status do
      :started ->
        :telemetry.execute(
          [:jido_lib, :github, :action, :start],
          %{system_time: System.system_time(), duration_ms: duration_ms},
          event_meta
        )

      :completed ->
        :telemetry.execute(
          [:jido_lib, :github, :action, :stop],
          %{system_time: System.system_time(), duration_ms: duration_ms},
          event_meta
        )

      :failed ->
        :telemetry.execute(
          [:jido_lib, :github, :action, :exception],
          %{system_time: System.system_time(), duration_ms: duration_ms},
          event_meta
        )

      _ ->
        :ok
    end

    :ok
  rescue
    _ -> :ok
  end

  defp telemetry_meta(intake) when is_map(intake) do
    %{
      run_id: Helpers.map_get(intake, :run_id),
      provider: Helpers.map_get(intake, :provider, :claude),
      agent_mode: Helpers.map_get(intake, :agent_mode),
      owner: Helpers.map_get(intake, :owner),
      repo: Helpers.map_get(intake, :repo),
      issue_number: Helpers.map_get(intake, :issue_number),
      session_id: Helpers.map_get(intake, :session_id),
      sprite_name: Helpers.map_get(intake, :sprite_name)
    }
  end

  defp duration_ms(measurements) when is_map(measurements) do
    case measurements[:duration] || measurements["duration"] do
      native when is_integer(native) -> System.convert_time_unit(native, :native, :millisecond)
      value when is_integer(value) -> value
      _ -> 0
    end
  end
end
