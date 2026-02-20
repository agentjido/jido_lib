defmodule Jido.Lib.Github.Actions.PostIssueCommentTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Actions.PostIssueComment

  setup do
    Jido.Lib.Test.FakeShellState.reset!()
    :ok
  end

  test "posts triage report comment and captures url" do
    params = %{
      comment_mode: :triage_report,
      owner: "test",
      repo: "repo",
      issue_number: 42,
      run_id: "run-123",
      session_id: "sess-123",
      workspace_dir: "/work/jido-triage-run-123",
      investigation: "report",
      investigation_status: :ok,
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(PostIssueComment, params, %{})
    assert result.comment_posted == true
    assert result.comment_url =~ "https://github.com/test/repo/issues/42"
  end

  test "posts PR link comment in repo dir" do
    params = %{
      comment_mode: :pr_link,
      owner: "test",
      repo: "repo",
      issue_number: 42,
      run_id: "run-123",
      repo_dir: "/work/repo",
      session_id: "sess-123",
      branch_name: "jido/prbot/issue-42-run-123",
      commit_sha: "head-sha-123",
      pr_url: "https://github.com/test/repo/pull/7",
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(PostIssueComment, params, %{})
    assert result.issue_comment_posted == true
    assert result.issue_comment_error == nil
  end

  test "captures non-fatal PR comment failure" do
    Jido.Lib.Test.FakeShellState.add_failure("gh issue comment", :api_down)

    params = %{
      comment_mode: :pr_link,
      owner: "test",
      repo: "repo",
      issue_number: 42,
      run_id: "run-123",
      repo_dir: "/work/repo",
      session_id: "sess-123",
      branch_name: "jido/prbot/issue-42-run-123",
      commit_sha: "head-sha-123",
      pr_url: "https://github.com/test/repo/pull/7",
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(PostIssueComment, params, %{})
    assert result.issue_comment_posted == false
    assert result.issue_comment_error =~ "api_down"
  end
end
