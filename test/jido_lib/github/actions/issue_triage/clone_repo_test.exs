defmodule Jido.Lib.Github.Actions.CloneRepoTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Actions.CloneRepo

  setup do
    Jido.Lib.Test.FakeShellState.reset!()
    :ok
  end

  test "clones repository into workspace" do
    params = %{
      owner: "test",
      repo: "myrepo",
      workspace_dir: "/work/jido-triage-run-123",
      session_id: "sess-123",
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(CloneRepo, params, %{})

    assert result.repo_dir == "/work/jido-triage-run-123/myrepo"
  end
end
