defmodule Jido.Lib.Github.ResultMapsTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Github.ResultMaps

  test "triage_result/3 builds canonical map" do
    intake = %{
      run_id: "abc123",
      provider: :claude,
      owner: "agentjido",
      repo: "jido",
      issue_number: 42
    }

    final = %{
      status: :completed,
      investigation: "report",
      investigation_status: :ok,
      agent_status: :ok,
      comment_posted: true,
      comment_url: "https://github.com/test/repo/issues/42#issuecomment-1",
      teardown_verified: true
    }

    result = ResultMaps.triage_result(intake, final, [final])

    assert result.status == :completed
    assert result.provider == :claude
    assert result.comment_posted == true
    assert result.teardown_verified == true
  end

  test "pr_result/3 builds canonical map" do
    intake = %{
      run_id: "abc123",
      provider: :codex,
      owner: "agentjido",
      repo: "jido",
      issue_number: 42
    }

    final = %{
      status: :completed,
      branch_name: "jido/prbot/issue-42-abc123",
      pr_created: true,
      pr_url: "https://github.com/agentjido/jido/pull/1",
      issue_comment_posted: true
    }

    result = ResultMaps.pr_result(intake, final, [final])

    assert result.status == :completed
    assert result.provider == :codex
    assert result.pr_created == true
    assert result.issue_comment_posted == true
  end
end
