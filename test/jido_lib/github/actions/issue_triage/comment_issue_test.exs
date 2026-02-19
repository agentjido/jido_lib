defmodule Jido.Lib.Github.Actions.IssueTriage.CommentIssueTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Actions.IssueTriage.CommentIssue

  setup do
    Jido.Lib.Test.FakeShellState.reset!()
    :ok
  end

  test "posts comment and captures url" do
    params = %{
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

    assert {:ok, result} = Jido.Exec.run(CommentIssue, params, %{})
    assert result.comment_posted == true
    assert result.comment_url =~ "https://github.com/test/repo/issues/42"
  end

  test "returns non-failing result when post fails" do
    Jido.Lib.Test.FakeShellState.add_failure("gh issue comment", :api_down)

    params = %{
      owner: "test",
      repo: "repo",
      issue_number: 42,
      run_id: "run-123",
      session_id: "sess-123",
      workspace_dir: "/work/jido-triage-run-123",
      investigation: "report",
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(CommentIssue, params, %{})
    assert result.comment_posted == false
    assert result.comment_error =~ "api_down"
  end
end
