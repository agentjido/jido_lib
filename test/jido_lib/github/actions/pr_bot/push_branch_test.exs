defmodule Jido.Lib.Github.Actions.PrBot.PushBranchTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Actions.PrBot.PushBranch

  defmodule WrongRemoteShellAgent do
    def run(_session_id, command, _opts \\ []) do
      if String.contains?(command, "git remote get-url origin") do
        {:ok, "https://github.com/other/repo.git"}
      else
        {:ok, "ok"}
      end
    end
  end

  setup do
    Jido.Lib.Test.FakeShellState.reset!()
    :ok
  end

  test "pushes branch when origin matches owner/repo" do
    params = %{
      owner: "test",
      repo: "repo",
      repo_dir: "/work/repo",
      session_id: "sess-123",
      branch_name: "jido/prbot/issue-42-run-123",
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(PushBranch, params, %{})
    assert result.branch_pushed == true
  end

  test "fails when origin remote does not match target repo" do
    params = %{
      owner: "test",
      repo: "repo",
      repo_dir: "/work/repo",
      session_id: "sess-123",
      branch_name: "jido/prbot/issue-42-run-123",
      shell_agent_mod: WrongRemoteShellAgent
    }

    assert {:error,
            %Jido.Action.Error.ExecutionFailureError{
              message: {:push_branch_failed, {:remote_mismatch, _}}
            }} = Jido.Exec.run(PushBranch, params, %{})
  end

  test "fails when git push fails" do
    Jido.Lib.Test.FakeShellState.add_failure("git push -u origin", :permission_denied)

    params = %{
      owner: "test",
      repo: "repo",
      repo_dir: "/work/repo",
      session_id: "sess-123",
      branch_name: "jido/prbot/issue-42-run-123",
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:error,
            %Jido.Action.Error.ExecutionFailureError{
              message: {:push_branch_failed, :permission_denied}
            }} = Jido.Exec.run(PushBranch, params, %{})
  end
end
