defmodule Jido.Lib.Github.Agents.RunicDelegatedChildWorker do
  @moduledoc """
  Runic delegated child worker that disables action timeout/retry for delegated execution.
  """

  use Jido.Agent,
    name: "runic_delegated_child_worker",
    schema: [
      status: [type: :atom, default: :idle]
    ]

  @runic_child_exec_opts [timeout: 0, max_retries: 0]

  @doc false
  @spec plugin_specs() :: [Jido.Plugin.Spec.t()]
  def plugin_specs, do: []

  @doc false
  def signal_routes(_ctx) do
    [
      {"runic.child.execute", __MODULE__.ExecuteAction}
    ]
  end

  @impl true
  def on_before_cmd(agent, {__MODULE__.ExecuteAction, params}) when is_map(params) do
    {:ok, agent, {__MODULE__.ExecuteAction, params, %{}, @runic_child_exec_opts}}
  end

  def on_before_cmd(agent, action), do: {:ok, agent, action}
end

defmodule Jido.Lib.Github.Agents.RunicDelegatedChildWorker.ExecuteAction do
  @moduledoc false

  use Jido.Action,
    name: "runic_delegated_execute_runnable",
    description: "Execute a delegated Runic Runnable and emit completion to parent",
    schema: [
      runnable: [type: :any, required: true],
      runnable_id: [type: :any, required: true],
      tag: [type: :any, required: true]
    ]

  alias Jido.Agent.Directive
  alias Jido.Runic.RunnableExecution

  @impl true
  def run(%{runnable: runnable, runnable_id: runnable_id, tag: _tag}, context) do
    if runnable.id != runnable_id do
      {:error, "Runnable ID mismatch: expected #{inspect(runnable_id)}, got #{inspect(runnable.id)}"}
    else
      executed = RunnableExecution.execute(runnable)
      result_signal = RunnableExecution.completion_signal(executed, source: "/runic/child")

      emit_directive = Directive.emit_to_parent(%Jido.Agent{state: context.state}, result_signal)
      {:ok, %{}, List.wrap(emit_directive)}
    end
  end
end
