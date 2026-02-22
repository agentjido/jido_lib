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

  test "from_output/1 parses critique from stream-json envelope" do
    payload =
      [
        Jason.encode!(%{"type" => "turn.started"}),
        Jason.encode!(%{
          "type" => "turn.completed",
          "output_text" =>
            Jason.encode!(%{
              verdict: "revise",
              severity: "medium",
              findings: [%{id: "f1", message: "missing test", impact: "risk"}],
              revision_instructions: "Add tests",
              confidence: 0.8
            })
        })
      ]
      |> Enum.join("\n")

    assert {:ok, critique} = CritiqueSchema.from_output(payload)
    assert critique.verdict == :revise
    assert critique.severity == :medium
    assert critique.confidence == 0.8
  end

  test "from_output/1 rejects ambiguous verdicts" do
    payload =
      [
        Jason.encode!(%{
          "type" => "turn.completed",
          "output_text" => Jason.encode!(%{verdict: "accept", severity: "low"})
        }),
        Jason.encode!(%{
          "type" => "turn.completed",
          "output_text" => Jason.encode!(%{verdict: "revise", severity: "medium"})
        })
      ]
      |> Enum.join("\n")

    assert {:error, {:ambiguous_critique_verdicts, verdicts}} =
             CritiqueSchema.from_output(payload)

    assert Enum.sort(verdicts) == [:accept, :revise]
  end

  test "from_text/1 falls back to heuristic parsing" do
    critique =
      CritiqueSchema.from_text("I accept the draft, but please revise it before posting.")

    assert critique.verdict == :revise
    assert critique.severity in [:medium, :high, :critical]
    assert is_list(critique.findings)
  end
end
