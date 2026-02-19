defmodule Jido.Lib.Github.Actions.PrBot.EnsureBranchTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Actions.PrBot.EnsureBranch

  setup do
    Jido.Lib.Test.FakeShellState.reset!()
    :ok
  end

  test "detects base branch and creates working branch" do
    params = %{
      owner: "test",
      repo: "repo",
      issue_number: 42,
      run_id: "run-123",
      repo_dir: "/work/repo",
      session_id: "sess-123",
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(EnsureBranch, params, %{})

    assert result.base_branch == "main"
    assert result.branch_name == "jido/prbot/issue-42-run-123"
    assert result.base_sha == "base-sha-main"
  end

  test "uses provided base branch override" do
    params = %{
      owner: "test",
      repo: "repo",
      issue_number: 42,
      run_id: "run-123",
      repo_dir: "/work/repo",
      session_id: "sess-123",
      base_branch: "develop",
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(EnsureBranch, params, %{})
    assert result.base_branch == "develop"
  end

  test "returns error when default branch query fails" do
    Jido.Lib.Test.FakeShellState.add_failure("gh repo view", :api_down)

    params = %{
      owner: "test",
      repo: "repo",
      issue_number: 42,
      run_id: "run-123",
      repo_dir: "/work/repo",
      session_id: "sess-123",
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:error,
            %Jido.Action.Error.ExecutionFailureError{
              message: {:ensure_branch_failed, :api_down}
            }} = Jido.Exec.run(EnsureBranch, params, %{})
  end
end
