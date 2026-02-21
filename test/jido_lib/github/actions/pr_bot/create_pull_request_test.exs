defmodule Jido.Lib.Github.Actions.CreatePullRequestTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Actions.CreatePullRequest

  defmodule ReusedPrShellAgent do
    def run(_session_id, command, _opts \\ []) do
      if String.contains?(command, "gh pr list") do
        {:ok,
         Jason.encode!([
           %{
             "number" => 99,
             "url" => "https://github.com/test/repo/pull/99",
             "title" => "Existing PR"
           }
         ])}
      else
        {:ok, "ok"}
      end
    end
  end

  setup do
    Jido.Lib.Test.FakeShellState.reset!()
    :ok
  end

  test "creates PR when no open PR exists for branch" do
    params = %{
      owner: "test",
      repo: "repo",
      issue_number: 42,
      issue_url: "https://github.com/test/repo/issues/42",
      issue_title: "Fix bug",
      run_id: "run-123",
      repo_dir: "/work/repo",
      session_id: "sess-123",
      branch_name: "jido/prbot/issue-42-run-123",
      base_branch: "main",
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(CreatePullRequest, params, %{})
    assert result.pr_created == true
    assert result.pr_number == 7
    assert result.pr_url == "https://github.com/test/repo/pull/7"
  end

  test "reuses existing open PR for branch" do
    params = %{
      owner: "test",
      repo: "repo",
      issue_number: 42,
      issue_url: "https://github.com/test/repo/issues/42",
      issue_title: "Fix bug",
      run_id: "run-123",
      repo_dir: "/work/repo",
      session_id: "sess-123",
      branch_name: "jido/prbot/issue-42-run-123",
      base_branch: "main",
      shell_agent_mod: ReusedPrShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(CreatePullRequest, params, %{})
    assert result.pr_created == false
    assert result.pr_number == 99
    assert result.pr_url == "https://github.com/test/repo/pull/99"
  end

  test "fails when gh pr create fails" do
    Jido.Lib.Test.FakeShellState.add_failure("gh pr create", :api_down)

    params = %{
      owner: "test",
      repo: "repo",
      issue_number: 42,
      issue_url: "https://github.com/test/repo/issues/42",
      issue_title: "Fix bug",
      run_id: "run-123",
      repo_dir: "/work/repo",
      session_id: "sess-123",
      branch_name: "jido/prbot/issue-42-run-123",
      base_branch: "main",
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:error,
            %Jido.Action.Error.ExecutionFailureError{
              message: {:create_pull_request_failed, :api_down}
            }} = Jido.Exec.run(CreatePullRequest, params, %{})
  end
end
