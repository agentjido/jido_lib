defmodule Jido.Lib.Bots.Foundation.Gate do
  @moduledoc """
  Pure decision gate for critique-driven writer/critic revision loops.
  """

  alias Jido.Lib.Bots.Foundation.CritiqueSchema

  @type decision :: :accepted | :revised | :rejected | :failed

  @spec decide(map() | CritiqueSchema.t(), non_neg_integer(), non_neg_integer()) :: map()
  def decide(critique, iteration, max_revisions)
      when is_integer(iteration) and iteration > 0 and is_integer(max_revisions) and
             max_revisions >= 0 do
    critique = normalize_critique(critique)
    route_verdict(critique, iteration, max_revisions)
  end

  def decide(_critique, _iteration, _max_revisions) do
    %{decision: :failed, should_revise: false, terminal: true, reason: :invalid_gate_input}
  end

  defp normalize_critique(%CritiqueSchema{} = critique), do: critique

  defp normalize_critique(%{} = critique) do
    case CritiqueSchema.new(critique) do
      {:ok, parsed} -> parsed
      {:error, _} -> CritiqueSchema.new!(%{verdict: :revise, findings: [], confidence: 0.0})
    end
  end

  defp normalize_critique(_),
    do: CritiqueSchema.new!(%{verdict: :revise, findings: [], confidence: 0.0})

  defp route_verdict(%CritiqueSchema{verdict: :accept}, iteration, _max_revisions),
    do: accepted_decision(iteration)

  defp route_verdict(%CritiqueSchema{verdict: :reject}, iteration, _max_revisions),
    do: terminal_rejection(iteration, :critic_reject)

  defp route_verdict(%CritiqueSchema{verdict: :revise} = critique, iteration, max_revisions),
    do: route_revision(critique, iteration, max_revisions)

  defp route_verdict(%CritiqueSchema{}, _iteration, _max_revisions),
    do: %{decision: :failed, should_revise: false, terminal: true, reason: :unknown_gate_state}

  defp route_revision(%CritiqueSchema{} = critique, iteration, max_revisions) do
    cond do
      critical_block?(critique) and iteration > max_revisions ->
        terminal_rejection(iteration, :critical_findings_after_budget)

      iteration <= max_revisions ->
        revise_decision(iteration)

      true ->
        terminal_rejection(iteration, :revision_budget_exhausted)
    end
  end

  defp accepted_decision(iteration) when iteration <= 1 do
    %{decision: :accepted, should_revise: false, terminal: true, reason: nil}
  end

  defp accepted_decision(_iteration) do
    %{decision: :revised, should_revise: false, terminal: true, reason: nil}
  end

  defp revise_decision(iteration) do
    %{decision: :revised, should_revise: true, terminal: false, reason: {:revise, iteration}}
  end

  defp terminal_rejection(_iteration, reason) do
    %{decision: :rejected, should_revise: false, terminal: true, reason: reason}
  end

  defp critical_block?(%CritiqueSchema{severity: severity}), do: severity in [:critical, :high]
end
