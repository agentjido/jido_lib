defmodule Jido.Lib.Github.Agents.PrBotTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Github.Agents.PrBot
  alias Runic.Workflow

  test "build_workflow contains provider-neutral coding node and PR nodes" do
    workflow = PrBot.build_workflow()
    components = Workflow.components(workflow)

    assert Map.has_key?(components, :prepare_provider_runtime)
    assert Map.has_key?(components, :ensure_branch)
    assert Map.has_key?(components, :run_coding_agent)
    assert Map.has_key?(components, :ensure_commit)
    assert Map.has_key?(components, :run_checks)
    assert Map.has_key?(components, :push_branch)
    assert Map.has_key?(components, :create_pull_request)
    assert Map.has_key?(components, :comment_issue_with_pr)

    assert components[:run_coding_agent].action_mod ==
             Jido.Lib.Github.Actions.PrBot.RunCodingAgent
  end
end
