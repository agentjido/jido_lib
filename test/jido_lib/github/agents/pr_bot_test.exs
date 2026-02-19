defmodule Jido.Lib.Github.Agents.PrBotTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Github.Agents.PrBot
  alias Runic.Workflow

  test "build_workflow contains delegated claude_code node and PR nodes" do
    workflow = PrBot.build_workflow()
    components = Workflow.components(workflow)

    assert Map.has_key?(components, :ensure_branch)
    assert Map.has_key?(components, :ensure_commit)
    assert Map.has_key?(components, :run_checks)
    assert Map.has_key?(components, :push_branch)
    assert Map.has_key?(components, :create_pull_request)
    assert Map.has_key?(components, :comment_issue_with_pr)

    assert %Jido.Runic.ActionNode{
             action_mod: Jido.Lib.Github.Actions.PrBot.ClaudeCode,
             executor: {:child, :claude_sprite}
           } = components[:claude_code]
  end
end
