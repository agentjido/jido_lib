defmodule Jido.Lib.Github.Agents.ClaudeSpriteAgentTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Github.Actions.IssueTriage.ExecuteDelegatedRunnable
  alias Jido.Lib.Github.Agents.ClaudeSpriteAgent

  test "exposes runic.child.execute route to delegated runnable executor" do
    assert [{"runic.child.execute", ExecuteDelegatedRunnable}] =
             ClaudeSpriteAgent.signal_routes(%{})
  end

  test "plugin_specs is empty" do
    assert [] == ClaudeSpriteAgent.plugin_specs()
  end

  test "rewrites delegated runnable execution with no retries and extended timeout" do
    action = {ExecuteDelegatedRunnable, %{runnable: %{}}}
    agent = %Jido.Agent{state: %{}}

    assert {:ok, ^agent, {ExecuteDelegatedRunnable, %{runnable: %{}}, %{}, opts}} =
             ClaudeSpriteAgent.on_before_cmd(agent, action)

    assert Keyword.get(opts, :max_retries) == 0
    assert Keyword.get(opts, :timeout) == 0
  end
end
