defmodule Jido.Lib.Github.Actions.FetchIssueTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Actions.FetchIssue

  setup do
    Jido.Lib.Test.FakeShellState.reset!()
    :ok
  end

  test "fetches issue details" do
    params = %{
      owner: "test",
      repo: "repo",
      issue_number: 42,
      session_id: "sess-123",
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(FetchIssue, params, %{})

    assert result.issue_title == "Bug: Widget crashes on nil"
    assert result.issue_body == "Widget.call/1 crashes when passed nil input."
    assert result.issue_labels == ["bug"]
    assert result.issue_author == "testuser"
    assert result.issue_url == "https://github.com/test/repo/issues/42"
  end
end
