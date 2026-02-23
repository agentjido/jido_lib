defmodule Jido.Lib.Github.Agents.RunicDelegatedChildWorkerTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Github.Agents.RunicDelegatedChildWorker

  test "on_before_cmd injects zero-timeout execution opts for delegated runnable action" do
    agent = RunicDelegatedChildWorker.new()

    action =
      {RunicDelegatedChildWorker.ExecuteAction,
       %{runnable: %{id: "r-1"}, runnable_id: "r-1", tag: :writer}}

    assert {:ok, ^agent,
            {RunicDelegatedChildWorker.ExecuteAction, %{runnable: %{id: "r-1"}, runnable_id: "r-1", tag: :writer}, %{},
             opts}} = RunicDelegatedChildWorker.on_before_cmd(agent, action)

    assert opts[:timeout] == 0
    assert opts[:max_retries] == 0
  end

  test "on_before_cmd leaves unrelated actions unchanged" do
    agent = RunicDelegatedChildWorker.new()
    action = {:other_action, %{}}

    assert {:ok, ^agent, ^action} = RunicDelegatedChildWorker.on_before_cmd(agent, action)
  end
end
