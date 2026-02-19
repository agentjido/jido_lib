defmodule Jido.Lib.Github.Actions.PrBot.RunChecksTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Actions.PrBot.RunChecks

  setup do
    Jido.Lib.Test.FakeShellState.reset!()
    :ok
  end

  test "runs all check commands and returns result details" do
    params = %{
      repo_dir: "/work/repo",
      session_id: "sess-123",
      check_commands: ["mix deps.get", "mix compile"],
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(RunChecks, params, %{})
    assert result.checks_passed == true
    assert length(result.check_results) == 2
    assert Enum.all?(result.check_results, &(&1.status == :ok))
  end

  test "fails when any check command fails" do
    Jido.Lib.Test.FakeShellState.add_failure("mix compile", :compile_failed)

    params = %{
      repo_dir: "/work/repo",
      session_id: "sess-123",
      check_commands: ["mix deps.get", "mix compile"],
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:error,
            %Jido.Action.Error.ExecutionFailureError{
              message: {:check_failed, "mix compile", :compile_failed, _results}
            }} = Jido.Exec.run(RunChecks, params, %{})
  end
end
