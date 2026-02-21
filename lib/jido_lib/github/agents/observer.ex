defmodule Jido.Lib.Github.Agents.Observer do
  @moduledoc """
  Dedicated observer process for streaming GitHub bot runtime/coding signals.
  """

  use GenServer

  alias Jido.Lib.Github.Plugins.Observability

  @idle_timeout_ms 120_000

  @type state :: %{
          shell: module(),
          label: String.t(),
          delta_count: non_neg_integer()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec notify(pid(), Jido.Signal.t()) :: :ok
  def notify(pid, %Jido.Signal{} = signal) when is_pid(pid) do
    GenServer.cast(pid, {:signal, signal})
  end

  @spec stop(pid()) :: :ok
  def stop(pid) when is_pid(pid) do
    GenServer.stop(pid, :normal)
    :ok
  rescue
    _ -> :ok
  end

  @impl true
  def init(opts) do
    shell = Keyword.fetch!(opts, :shell)
    label = Keyword.fetch!(opts, :label)

    {:ok, %{shell: shell, label: label, delta_count: 0}, @idle_timeout_ms}
  end

  @impl true
  def handle_cast(
        {:signal, %Jido.Signal{type: type, data: data}},
        %{shell: shell, label: label} = state
      ) do
    next_count = Observability.print_signal(shell, label, type, data, state.delta_count)
    {:noreply, %{state | delta_count: next_count}, @idle_timeout_ms}
  end

  def handle_cast(_msg, state), do: {:noreply, state, @idle_timeout_ms}

  @impl true
  def handle_info(
        {:jido_lib_signal, %Jido.Signal{type: type, data: data}},
        %{shell: shell, label: label} = state
      ) do
    next_count = Observability.print_signal(shell, label, type, data, state.delta_count)
    {:noreply, %{state | delta_count: next_count}, @idle_timeout_ms}
  end

  def handle_info(:timeout, state), do: {:stop, :normal, state}
  def handle_info(_msg, state), do: {:noreply, state, @idle_timeout_ms}
end
