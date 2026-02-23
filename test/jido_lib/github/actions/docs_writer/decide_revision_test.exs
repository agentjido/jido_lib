defmodule Jido.Lib.Github.Actions.DocsWriter.DecideRevisionTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Github.Actions.DocsWriter.DecideRevision

  test "sets needs_revision for revise verdict on iteration 1" do
    params = %{
      iteration: 1,
      max_revisions: 1,
      run_id: "run-docs-gate",
      critique_v1: %{verdict: :revise, severity: :medium, findings: []}
    }

    assert {:ok, result} = Jido.Exec.run(DecideRevision, params, %{})
    assert result.needs_revision == true
    assert result.gate_v1.decision == :revised
  end

  test "sets terminal decision for accepted verdict on iteration 2" do
    params = %{
      iteration: 2,
      max_revisions: 1,
      run_id: "run-docs-gate",
      critique_v2: %{verdict: :accept, severity: :low, findings: []}
    }

    assert {:ok, result} = Jido.Exec.run(DecideRevision, params, %{})
    assert result.needs_revision == false
    assert result.final_decision in [:accepted, :revised]
  end
end
