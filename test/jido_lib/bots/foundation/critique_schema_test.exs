defmodule Jido.Lib.Bots.Foundation.CritiqueSchemaTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Bots.Foundation.CritiqueSchema

  test "from_json/1 parses strict critique payload" do
    payload =
      Jason.encode!(%{
        verdict: "accept",
        severity: "low",
        findings: [%{id: "f1", message: "looks good"}],
        revision_instructions: "",
        confidence: 0.95
      })

    assert {:ok, critique} = CritiqueSchema.from_json(payload)
    assert critique.verdict == :accept
    assert critique.severity == :low
    assert critique.confidence == 0.95
  end

  test "from_text/1 falls back to heuristic parsing" do
    critique = CritiqueSchema.from_text("Critical blocker: missing tests, please revise")

    assert critique.verdict in [:revise, :reject]
    assert critique.severity in [:high, :critical]
    assert is_list(critique.findings)
  end
end
