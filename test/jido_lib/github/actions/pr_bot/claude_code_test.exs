defmodule Jido.Lib.Github.Actions.PrBot.ClaudeCodeTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Actions.PrBot.ClaudeCode

  setup do
    Jido.Lib.Test.FakeShellState.reset!()
    :ok
  end

  test "returns claude summary and emits pr_bot signals" do
    params = %{
      repo_dir: "/work/repo",
      session_id: "sess-123",
      issue_number: 42,
      issue_title: "Crash on nil",
      issue_body: "Body",
      run_id: "run-123",
      observer_pid: self(),
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(ClaudeCode, params, %{})
    assert result.claude_status == :ok
    assert result.claude_summary =~ "Investigation Report"

    assert_receive {:jido_lib_signal, %Jido.Signal{type: "jido.lib.github.pr_bot.claude.started"}}
    assert_receive {:jido_lib_signal, %Jido.Signal{type: "jido.lib.github.pr_bot.claude.mode"}}

    assert_receive {:jido_lib_signal,
                    %Jido.Signal{type: "jido.lib.github.pr_bot.claude.completed"}}
  end

  test "returns execution failure when claude run fails" do
    Jido.Lib.Test.FakeShellState.add_failure("claude -p", :timeout)

    params = %{
      repo_dir: "/work/repo",
      session_id: "sess-123",
      issue_number: 42,
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:error,
            %Jido.Action.Error.ExecutionFailureError{
              message: {:claude_code_failed, :timeout}
            }} = Jido.Exec.run(ClaudeCode, params, %{})
  end
end
