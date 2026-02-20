defmodule Jido.Lib.Github.Actions.EnsureCommitTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Actions.EnsureCommit

  defmodule FallbackShellAgent do
    def run(_session_id, command, _opts \\ []) do
      cond do
        String.contains?(command, "git rev-list --count") ->
          if Process.get(:fallback_commit_done) do
            {:ok, "1"}
          else
            {:ok, "0"}
          end

        String.contains?(command, "git status --porcelain") ->
          if Process.get(:fallback_commit_done) do
            {:ok, ""}
          else
            {:ok, " M lib/example.ex"}
          end

        String.contains?(command, "git add -A && git commit -m") ->
          Process.put(:fallback_commit_done, true)
          {:ok, "[feature 123] fix(repo): address issue #42"}

        String.contains?(command, "git rev-parse HEAD") ->
          {:ok, "head-sha-fallback"}

        true ->
          {:ok, "ok"}
      end
    end
  end

  defmodule NoChangesShellAgent do
    def run(_session_id, command, _opts \\ []) do
      cond do
        String.contains?(command, "git rev-list --count") -> {:ok, "0"}
        String.contains?(command, "git status --porcelain") -> {:ok, ""}
        String.contains?(command, "git rev-parse HEAD") -> {:ok, ""}
        true -> {:ok, "ok"}
      end
    end
  end

  setup do
    Jido.Lib.Test.FakeShellState.reset!()
    Process.delete(:fallback_commit_done)
    :ok
  end

  test "passes when commit already exists" do
    params = %{
      repo: "repo",
      issue_number: 42,
      repo_dir: "/work/repo",
      session_id: "sess-123",
      base_sha: "base-sha-main",
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(EnsureCommit, params, %{})
    assert result.commits_since_base == 1
    assert result.commit_sha == "head-sha-123"
    assert result.fallback_commit_used == false
  end

  test "creates fallback commit when tree is dirty and no commit exists" do
    params = %{
      repo: "repo",
      issue_number: 42,
      repo_dir: "/work/repo",
      session_id: "sess-123",
      base_sha: "base-sha-main",
      shell_agent_mod: FallbackShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(EnsureCommit, params, %{})
    assert result.fallback_commit_used == true
    assert result.commits_since_base == 1
    assert result.commit_sha == "head-sha-fallback"
  end

  test "fails when there are no changes to commit" do
    params = %{
      repo: "repo",
      issue_number: 42,
      repo_dir: "/work/repo",
      session_id: "sess-123",
      base_sha: "base-sha-main",
      shell_agent_mod: NoChangesShellAgent
    }

    assert {:error,
            %Jido.Action.Error.ExecutionFailureError{
              message: {:ensure_commit_failed, :no_changes}
            }} = Jido.Exec.run(EnsureCommit, params, %{})
  end
end
