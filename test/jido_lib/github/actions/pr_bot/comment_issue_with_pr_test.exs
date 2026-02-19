defmodule Jido.Lib.Github.Actions.PrBot.CommentIssueWithPrTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Actions.PrBot.CommentIssueWithPr

  setup do
    Jido.Lib.Test.FakeShellState.reset!()
    :ok
  end

  test "posts issue comment with PR URL" do
    params = %{
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

    assert {:ok, result} = Jido.Exec.run(CommentIssueWithPr, params, %{})
    assert result.issue_comment_posted == true
    assert result.issue_comment_error == nil
  end

  test "captures non-fatal issue comment failure" do
    Jido.Lib.Test.FakeShellState.add_failure("gh issue comment", :api_down)

    params = %{
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

    assert {:ok, result} = Jido.Exec.run(CommentIssueWithPr, params, %{})
    assert result.issue_comment_posted == false
    assert result.issue_comment_error =~ "api_down"
  end
end
