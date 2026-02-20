defmodule Jido.Lib.Github.Actions.RunCodingAgentCodingTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Actions.RunCodingAgent

  setup do
    Jido.Lib.Test.FakeShellState.reset!()
    :ok
  end

  test "runs coding agent and returns agent summary" do
    params = %{
      provider: :claude,
      agent_mode: :coding,
      repo_dir: "/work/repo",
      session_id: "sess-123",
      issue_number: 42,
      issue_title: "Crash on nil",
      issue_body: "Body",
      run_id: "run-123",
      observer_pid: self(),
      provider_runtime_ready: true,
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(RunCodingAgent, params, %{})
    assert result.provider == :claude
    assert result.agent_status == :ok
    assert result.agent_summary =~ "Investigation Report"

    assert_receive {:jido_lib_signal, %Jido.Signal{type: "jido.lib.github.coding_agent.started"}}

    assert_receive {:jido_lib_signal, %Jido.Signal{type: "jido.lib.github.coding_agent.mode"}}

    assert_receive {:jido_lib_signal,
                    %Jido.Signal{type: "jido.lib.github.coding_agent.completed"}}
  end

  test "returns execution failure when coding agent command fails" do
    Jido.Lib.Test.FakeShellState.add_failure("claude -p", :timeout)

    params = %{
      provider: :claude,
      agent_mode: :coding,
      repo_dir: "/work/repo",
      session_id: "sess-123",
      issue_number: 42,
      provider_runtime_ready: true,
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:error,
            %Jido.Action.Error.ExecutionFailureError{
              message: {:run_coding_agent_failed, _reason}
            }} = Jido.Exec.run(RunCodingAgent, params, %{})
  end

  test "returns execution failure when runtime is not prepared" do
    params = %{
      provider: :claude,
      agent_mode: :coding,
      repo_dir: "/work/repo",
      session_id: "sess-123",
      issue_number: 42,
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:error,
            %Jido.Action.Error.ExecutionFailureError{
              message: {:run_coding_agent_failed, :provider_runtime_not_ready}
            }} = Jido.Exec.run(RunCodingAgent, params, %{})
  end
end
