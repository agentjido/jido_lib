defmodule Jido.Lib.Github.Actions.RunRepoCommandsTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Actions.RunRepoCommands

  setup do
    Jido.Lib.Test.FakeShellState.reset!()
    :ok
  end

  test "runs setup commands in repo dir" do
    params = %{
      phase: :setup,
      repo_dir: "/work/repo",
      session_id: "sess-123",
      setup_commands: ["mix deps.get", "mix compile"],
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(RunRepoCommands, params, %{})
    assert result.repo_dir == "/work/repo"

    runs = Jido.Lib.Test.FakeShellState.runs()

    assert Enum.any?(runs, fn {_sid, cmd} ->
             String.contains?(cmd, "cd '/work/repo' && mix deps.get")
           end)

    assert Enum.any?(runs, fn {_sid, cmd} ->
             String.contains?(cmd, "cd '/work/repo' && mix compile")
           end)
  end

  test "runs all check commands and returns result details" do
    params = %{
      phase: :checks,
      return_results: true,
      repo_dir: "/work/repo",
      session_id: "sess-123",
      check_commands: ["mix deps.get", "mix compile"],
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(RunRepoCommands, params, %{})
    assert result.checks_passed == true
    assert length(result.check_results) == 2
    assert Enum.all?(result.check_results, &(&1.status == :ok))
  end

  test "fails when any check command fails" do
    Jido.Lib.Test.FakeShellState.add_failure("mix compile", :compile_failed)

    params = %{
      phase: :checks,
      return_results: true,
      repo_dir: "/work/repo",
      session_id: "sess-123",
      check_commands: ["mix deps.get", "mix compile"],
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:error,
            %Jido.Action.Error.ExecutionFailureError{
              message: {:check_failed, "mix compile", :compile_failed, _results}
            }} = Jido.Exec.run(RunRepoCommands, params, %{})
  end

  test "infers checks phase from commit_sha when phase is omitted" do
    params = %{
      commit_sha: "abc123",
      return_results: true,
      repo_dir: "/work/repo",
      session_id: "sess-123",
      check_commands: ["mix deps.get"],
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(RunRepoCommands, params, %{})
    assert result.checks_passed == true
    assert [%{cmd: "mix deps.get", status: :ok}] = result.check_results
  end
end
