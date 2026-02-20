defmodule Jido.Lib.Github.Actions.IssueTriage.RunCodingAgentTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Actions.IssueTriage.RunCodingAgent

  setup do
    Jido.Lib.Test.FakeShellState.reset!()
    :ok
  end

  test "runs coding agent and returns investigation output" do
    params = %{
      provider: :claude,
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
    assert result.investigation_status == :ok
    assert result.agent_status == :ok
    assert result.agent_summary =~ "Investigation Report"

    assert_receive {:jido_lib_signal,
                    %Jido.Signal{type: "jido.lib.github.issue_triage.coding_agent.started"}}

    assert_receive {:jido_lib_signal,
                    %Jido.Signal{type: "jido.lib.github.issue_triage.coding_agent.mode"}}

    assert_receive {:jido_lib_signal,
                    %Jido.Signal{type: "jido.lib.github.issue_triage.coding_agent.completed"}}
  end

  test "returns failed investigation state when provider stream command fails" do
    Jido.Lib.Test.FakeShellState.add_failure("claude -p", :timeout)

    params = %{
      provider: :claude,
      repo_dir: "/work/repo",
      session_id: "sess-123",
      issue_number: 42,
      run_id: "run-123",
      provider_runtime_ready: true,
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(RunCodingAgent, params, %{})
    assert result.investigation_status == :failed
    assert result.agent_status == :failed
    assert is_binary(result.agent_error)
  end

  test "returns failed state when provider runtime has not been prepared" do
    params = %{
      provider: :claude,
      repo_dir: "/work/repo",
      session_id: "sess-123",
      issue_number: 42,
      run_id: "run-123",
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(RunCodingAgent, params, %{})
    assert result.investigation_status == :failed
    assert result.agent_status == :failed
    assert result.agent_error =~ "provider_runtime_not_ready"
  end
end
