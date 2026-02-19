defmodule Jido.Lib.Github.Actions.IssueTriage.ExecuteDelegatedRunnable do
  @moduledoc """
  Execute a delegated Runic runnable in a child agent and emit the result to the parent.
  """

  use Jido.Action,
    name: "execute_delegated_runnable",
    description: "Execute delegated runnable and emit completion to parent",
    schema: [
      runnable: [type: :any, required: true],
      runnable_id: [type: :any, required: true],
      tag: [type: :any, required: true]
    ]

  alias Jido.Agent.Directive
  alias Jido.Runic.RunnableExecution
  alias Runic.Workflow.Runnable

  @signal_source "/github/issue_triage/bot2/child"

  @impl true
  def run(%{runnable: runnable, runnable_id: runnable_id, tag: tag}, context) do
    if runnable.id != runnable_id do
      {:error, "Runnable ID mismatch: expected #{inspect(runnable_id)}, got #{inspect(runnable.id)}"}
    else
      emit_delegate_signal(observer_pid(runnable), "started", delegate_payload(runnable, tag))

      executed = RunnableExecution.execute(runnable)

      status_suffix =
        case executed.status do
          status when status in [:completed, :skipped] -> "completed"
          _ -> "failed"
        end

      emit_delegate_signal(
        observer_pid(runnable),
        status_suffix,
        Map.merge(delegate_payload(runnable, tag), %{
          status: executed.status,
          error: normalize_error(executed.error)
        })
      )

      result_signal = RunnableExecution.completion_signal(executed, source: @signal_source)
      emit_directive = Directive.emit_to_parent(%Jido.Agent{state: context.state}, result_signal)

      {:ok, %{}, List.wrap(emit_directive)}
    end
  end

  defp delegate_payload(%Runnable{} = runnable, tag) do
    value = runnable_value(runnable)
    node = runnable.node

    %{
      tag: tag,
      runnable_id: runnable.id,
      node: Map.get(node, :name) || Map.get(node, :hash),
      run_id: map_get(value, :run_id),
      issue_number: map_get(value, :issue_number),
      session_id: map_get(value, :session_id)
    }
  end

  defp normalize_error(nil), do: nil
  defp normalize_error(error), do: inspect(error)

  defp observer_pid(%Runnable{} = runnable) do
    value = runnable_value(runnable)

    case map_get(value, :observer_pid) do
      pid when is_pid(pid) -> pid
      _ -> nil
    end
  end

  defp runnable_value(%Runnable{input_fact: %{value: value}}) when is_map(value), do: value
  defp runnable_value(_), do: %{}

  defp map_get(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp emit_delegate_signal(pid, suffix, data) when is_pid(pid) and is_binary(suffix) do
    signal =
      Jido.Signal.new!(
        "jido.lib.github.issue_triage.delegate.#{suffix}",
        data,
        source: @signal_source
      )

    send(pid, {:jido_lib_signal, signal})
    :ok
  end

  defp emit_delegate_signal(_pid, _suffix, _data), do: :ok
end
