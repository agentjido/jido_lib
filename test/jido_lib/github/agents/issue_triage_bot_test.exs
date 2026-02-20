defmodule Jido.Lib.Github.Agents.IssueTriageBotTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Github.Agents.IssueTriageBot
  alias Runic.Workflow

  test "build_workflow contains provider-neutral coding nodes" do
    workflow = IssueTriageBot.build_workflow()
    components = Workflow.components(workflow)

    assert Map.has_key?(components, :validate_host_env)
    assert Map.has_key?(components, :prepare_github_auth)
    assert Map.has_key?(components, :prepare_provider_runtime)
    assert Map.has_key?(components, :run_coding_agent)

    assert components[:run_coding_agent].action_mod ==
             Jido.Lib.Github.Actions.IssueTriage.RunCodingAgent
  end
end
