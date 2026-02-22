defmodule Jido.Lib.Github.Actions.TriageCritic.DecideRevisionTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Github.Actions.TriageCritic.DecideRevision

  test "sets needs_revision when v1 critique requests revise" do
    params = %{
      iteration: 1,
      run_id: "run-gate",
      max_revisions: 1,
      critique_v1: %{verdict: :revise, severity: :medium, findings: []}
    }

    assert {:ok, result} = Jido.Exec.run(DecideRevision, params, %{})
    assert result.needs_revision == true
    assert result.gate_v1.decision == :revised
  end

  test "sets final decision on second pass" do
    params = %{
      iteration: 2,
      run_id: "run-gate-2",
      max_revisions: 1,
      needs_revision: true,
      critique_v2: %{verdict: :accept, severity: :low, findings: []}
    }

    assert {:ok, result} = Jido.Exec.run(DecideRevision, params, %{})
    assert result.final_decision == :revised
    assert result.gate_v2.decision == :revised
  end
end
