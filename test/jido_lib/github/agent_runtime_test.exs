defmodule Jido.Lib.Github.AgentRuntimeTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Github.AgentRuntime
  alias Jido.Lib.Github.Agents.IssueTriageBot

  test "run_pipeline/3 fails fast for invalid jido instance" do
    assert {:error, {:invalid_jido_instance, "bad-instance"}, run} =
             AgentRuntime.run_pipeline(IssueTriageBot, %{},
               jido: "bad-instance",
               timeout: 1_000
             )

    assert run == AgentRuntime.empty_run()
  end

  test "run_pipeline/3 fails fast when jido registry is unavailable" do
    assert {:error, {:jido_not_started, :missing_jido}, run} =
             AgentRuntime.run_pipeline(IssueTriageBot, %{},
               jido: :missing_jido,
               timeout: 1_000
             )

    assert run == AgentRuntime.empty_run()
  end

  test "empty_run/0 returns canonical empty snapshot" do
    run = AgentRuntime.empty_run()

    assert run.productions == []
    assert run.facts == []
    assert run.failures == []
    assert run.events == []
    assert run.status == :unknown
  end
end
