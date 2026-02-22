defmodule Jido.Lib.Bots.Runtime do
  @moduledoc """
  Shared runtime helpers for GitHub bots.

  Wraps `Jido.Lib.Github.AgentRuntime` with consistent lifecycle signaling,
  timeout defaults, and result normalization.
  """

  alias Jido.Lib.Bots.Result
  alias Jido.Lib.Github.AgentRuntime
  alias Jido.Lib.Github.Helpers
  alias Jido.Lib.Github.Observe
  alias Jido.Lib.Signal.{BotRunCompleted, BotRunFailed, BotRunStarted}

  @default_timeout_ms 600_000

  @spec run_pipeline(module(), map(), keyword(), keyword()) ::
          {:ok, map()} | {:error, term(), map()}
  def run_pipeline(agent_module, intake, runtime_opts \\ [], bot_opts \\ [])
      when is_atom(agent_module) and is_map(intake) and is_list(runtime_opts) and
             is_list(bot_opts) do
    observer_pid =
      Keyword.get(runtime_opts, :observer_pid) || Helpers.map_get(intake, :observer_pid)

    timeout =
      Keyword.get(runtime_opts, :timeout, Helpers.map_get(intake, :timeout, @default_timeout_ms))

    jido = Keyword.fetch!(runtime_opts, :jido)
    debug = Keyword.get(runtime_opts, :debug, true)
    sprite_prefix = Keyword.get(runtime_opts, :sprite_prefix, "jido-bot")
    bot_name = Keyword.get(bot_opts, :bot_name, agent_module)

    meta = Result.meta_from_intake(intake) |> Map.put(:bot, inspect(bot_name))

    emit_signal(observer_pid, BotRunStarted, Map.put(meta, :timeout, timeout))
    Observe.emit(Observe.pipeline(:start), %{system_time: System.system_time()}, meta)

    result =
      AgentRuntime.run_pipeline(agent_module, intake,
        jido: jido,
        timeout: timeout,
        debug: debug,
        observer_pid: observer_pid,
        sprite_prefix: sprite_prefix
      )

    case result do
      {:ok, run} ->
        emit_signal(
          observer_pid,
          BotRunCompleted,
          Map.merge(meta, %{status: run.status, error: nil})
        )

        Observe.emit(
          Observe.pipeline(:stop),
          %{system_time: System.system_time()},
          Map.merge(meta, %{status: run.status, error: inspect(run.error)})
        )

      {:error, reason, run} ->
        emit_signal(
          observer_pid,
          BotRunFailed,
          Map.merge(meta, %{status: run.status, error: inspect(reason)})
        )

        Observe.emit(
          Observe.pipeline(:exception),
          %{system_time: System.system_time()},
          Map.merge(meta, %{status: run.status, error: inspect(reason)})
        )
    end

    result
  end

  defp emit_signal(pid, signal_module, attrs) when is_pid(pid) and is_map(attrs) do
    signal = signal_module.new!(attrs)
    send(pid, {:jido_lib_signal, signal})
    :ok
  rescue
    _ -> :ok
  end

  defp emit_signal(_pid, _signal_module, _attrs), do: :ok
end
