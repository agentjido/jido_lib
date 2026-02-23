defmodule Jido.Lib.Github.Actions.DocsWriter.DecideRevision do
  @moduledoc """
  Applies revision gate logic for v1/v2 critique reports.
  """

  use Jido.Action,
    name: "docs_writer_decide_revision",
    description: "Decide whether to revise or finalize based on critique",
    compensation: [max_retries: 0],
    schema: [
      iteration: [type: :integer, required: true],
      max_revisions: [type: :integer, default: 1],
      single_pass: [type: :boolean, default: false],
      critique_v1: [type: {:or, [:map, nil]}, default: nil],
      critique_v2: [type: {:or, [:map, nil]}, default: nil],
      run_id: [type: :string, required: true]
    ]

  alias Jido.Lib.Bots.Foundation.Gate
  alias Jido.Lib.Github.Actions.DocsWriter.Helpers

  @impl true
  def run(params, _context) do
    iteration = params.iteration
    critique = select_critique(params, iteration)

    cond do
      params[:single_pass] == true and iteration == 1 ->
        {:ok, persist_single_pass_gate(params)}

      params[:single_pass] == true ->
        {:ok, Helpers.pass_through(params)}

      is_nil(critique) and iteration == 2 and params[:needs_revision] != true ->
        {:ok, Helpers.pass_through(params)}

      is_nil(critique) ->
        {:error, {:docs_decide_revision_failed, :missing_critique}}

      true ->
        gate = Gate.decide(critique, iteration, params.max_revisions)
        handle_gate_result(params, iteration, gate)
    end
  end

  defp persist_single_pass_gate(params) do
    gate = %{
      decision: :accepted,
      should_revise: false,
      terminal: true,
      reason: :single_pass
    }

    Helpers.pass_through(params)
    |> Map.put(:gate_v1, gate)
    |> Map.put(:needs_revision, false)
    |> Map.put(:final_decision, :accepted)
  end

  defp handle_gate_result(_params, _iteration, %{decision: :failed, reason: reason}) do
    {:error, {:docs_decide_revision_failed, reason}}
  end

  defp handle_gate_result(params, iteration, gate) do
    persist_gate(params, iteration, gate)
  end

  defp persist_gate(params, 1, gate) do
    {:ok,
     Helpers.pass_through(params)
     |> Map.put(:gate_v1, gate)
     |> Map.put(:needs_revision, gate.should_revise)
     |> maybe_put_final_decision(gate)}
  end

  defp persist_gate(params, 2, gate) do
    {:ok,
     Helpers.pass_through(params)
     |> Map.put(:gate_v2, gate)
     |> Map.put(:needs_revision, false)
     |> maybe_put_final_decision(gate)}
  end

  defp maybe_put_final_decision(map, %{terminal: true} = gate),
    do: Map.put(map, :final_decision, gate.decision)

  defp maybe_put_final_decision(map, _gate), do: map

  defp select_critique(params, 1), do: params[:critique_v1]
  defp select_critique(params, 2), do: params[:critique_v2]
  defp select_critique(_params, _other), do: nil
end
