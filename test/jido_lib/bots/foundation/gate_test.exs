defmodule Jido.Lib.Bots.Foundation.GateTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Bots.Foundation.Gate

  test "accept verdict terminates with accepted decision" do
    decision = Gate.decide(%{verdict: :accept, severity: :low, findings: []}, 1, 1)

    assert decision.decision == :accepted
    assert decision.terminal == true
    assert decision.should_revise == false
  end

  test "revise verdict triggers one revision when budget allows" do
    decision = Gate.decide(%{verdict: :revise, severity: :medium, findings: []}, 1, 1)

    assert decision.decision == :revised
    assert decision.terminal == false
    assert decision.should_revise == true
  end

  test "revise verdict becomes rejection when budget exhausted" do
    decision = Gate.decide(%{verdict: :revise, severity: :medium, findings: []}, 2, 1)

    assert decision.decision == :rejected
    assert decision.terminal == true
    assert decision.should_revise == false
  end

  test "invalid critique input fails closed" do
    decision = Gate.decide(nil, 1, 1)

    assert decision.decision == :failed
    assert decision.terminal == true
    assert decision.should_revise == false
  end
end
