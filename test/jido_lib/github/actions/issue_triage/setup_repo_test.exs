defmodule Jido.Lib.Github.Actions.IssueTriage.SetupRepoTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Actions.IssueTriage.SetupRepo

  setup do
    Jido.Lib.Test.FakeShellState.reset!()
    :ok
  end

  test "runs setup commands in repo dir" do
    params = %{
      repo_dir: "/work/repo",
      session_id: "sess-123",
      setup_commands: ["mix deps.get", "mix compile"],
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(SetupRepo, params, %{})
    assert result.repo_dir == "/work/repo"

    runs = Jido.Lib.Test.FakeShellState.runs()

    assert Enum.any?(runs, fn {_sid, cmd} ->
             String.contains?(cmd, "cd '/work/repo' && mix deps.get")
           end)

    assert Enum.any?(runs, fn {_sid, cmd} ->
             String.contains?(cmd, "cd '/work/repo' && mix compile")
           end)
  end
end
