defmodule Jido.Lib.Github.Agents.IssueTriageBotTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Github.Agents.IssueTriageBot
  alias Runic.Workflow

  test "build_workflow contains validate_host_env and delegated claude node" do
    workflow = IssueTriageBot.build_workflow()
    components = Workflow.components(workflow)

    assert Map.has_key?(components, :validate_host_env)
    assert Map.has_key?(components, :prepare_github_auth)

    assert %Jido.Runic.ActionNode{
             action_mod: Jido.Lib.Github.Actions.IssueTriage.Claude,
             executor: {:child, :claude_sprite}
           } = components[:claude]
  end
end
