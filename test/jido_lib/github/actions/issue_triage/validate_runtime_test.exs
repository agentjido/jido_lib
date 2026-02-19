defmodule Jido.Lib.Github.Actions.IssueTriage.ValidateRuntimeTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Actions.IssueTriage.ValidateRuntime

  setup do
    Jido.Lib.Test.FakeShellState.reset!()
    :ok
  end

  test "returns runtime checks when required tools and env are present" do
    params = %{
      session_id: "sess-123",
      run_id: "run-123",
      issue_number: 42,
      observer_pid: self(),
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(ValidateRuntime, params, %{})
    assert result.runtime_checks.gh == true
    assert result.runtime_checks.git == true
    assert result.runtime_checks.claude == true
    assert result.runtime_checks.base_url_present == true
    assert result.runtime_checks.auth_source == "ANTHROPIC_AUTH_TOKEN"

    assert_receive {:jido_lib_signal,
                    %Jido.Signal{
                      type: "jido.lib.github.issue_triage.validate_runtime.checked",
                      data: %{runtime_checks: %{gh: true, claude: true}}
                    }}
  end

  test "fails when required runtime checks are missing" do
    Jido.Lib.Test.FakeShellState.add_failure("command -v claude", :missing)

    params = %{
      session_id: "sess-123",
      run_id: "run-123",
      issue_number: 42,
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:error,
            %Jido.Action.Error.ExecutionFailureError{
              message: {:validate_runtime_failed, %{missing: missing}}
            }} =
             Jido.Exec.run(ValidateRuntime, params, %{})

    assert :missing_claude in missing
  end
end
