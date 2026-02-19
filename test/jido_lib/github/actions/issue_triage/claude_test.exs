defmodule Jido.Lib.Github.Actions.IssueTriage.ClaudeTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Actions.IssueTriage.Claude
  @cancel_probe_name :jido_lib_claude_timeout_probe

  defmodule TimeoutSessionServer do
    def subscribe(_session_id, _pid), do: {:ok, :subscribed}
    def unsubscribe(_session_id, _pid), do: {:ok, :unsubscribed}
    def run_command(_session_id, _line, _opts), do: {:ok, :accepted}

    def cancel(session_id) do
      if pid = Process.whereis(:jido_lib_claude_timeout_probe) do
        send(pid, {:cancel_called, session_id})
      end

      {:ok, :cancelled}
    end
  end

  defmodule RawLineShellAgent do
    def run(_session_id, command, _opts \\ []) do
      if String.contains?(command, "claude -p") do
        {:ok, "{\"type\":\"system\"}\nNOT_JSON_LINE\n{\"type\":\"result\",\"result\":\"ok\"}"}
      else
        {:ok, "ok"}
      end
    end
  end

  setup do
    Jido.Lib.Test.FakeShellState.reset!()
    :ok
  end

  test "returns investigation output" do
    params = %{
      repo_dir: "/work/repo",
      session_id: "sess-123",
      issue_number: 42,
      issue_title: "Crash on nil",
      issue_body: "Body",
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(Claude, params, %{})
    assert result.investigation_status == :ok
    assert result.investigation =~ "Investigation Report"

    runs = Jido.Lib.Test.FakeShellState.runs()

    assert Enum.any?(runs, fn {_session_id, command} ->
             String.contains?(command, "--output-format stream-json")
           end)
  end

  test "returns failed status when claude command fails" do
    Jido.Lib.Test.FakeShellState.add_failure("claude -p", :timeout)

    params = %{
      repo_dir: "/work/repo",
      session_id: "sess-123",
      issue_number: 42,
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(Claude, params, %{})
    assert result.investigation_status == :failed
    assert result.investigation == nil
    assert result.investigation_error =~ "timeout"
  end

  test "emits probe signals when observer_pid is provided" do
    params = %{
      repo_dir: "/work/repo",
      session_id: "sess-123",
      issue_number: 42,
      observer_pid: self(),
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(Claude, params, %{})
    assert result.investigation_status == :ok

    assert_receive {:jido_lib_signal,
                    %Jido.Signal{type: "jido.lib.github.issue_triage.claude_probe.started"}}

    assert_receive {:jido_lib_signal,
                    %Jido.Signal{
                      type: "jido.lib.github.issue_triage.claude_probe.mode",
                      data: %{mode: "shell_agent_fallback"}
                    }}

    assert_receive {:jido_lib_signal,
                    %Jido.Signal{
                      type: "jido.lib.github.issue_triage.claude_probe.event",
                      data: %{event_kind: "result"}
                    }}

    assert_receive {:jido_lib_signal,
                    %Jido.Signal{type: "jido.lib.github.issue_triage.claude_probe.completed"}}
  end

  test "emits raw_line signal for non-json stream lines" do
    params = %{
      repo_dir: "/work/repo",
      session_id: "sess-123",
      issue_number: 42,
      observer_pid: self(),
      shell_agent_mod: RawLineShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(Claude, params, %{})
    assert result.investigation_status == :ok

    assert_receive {:jido_lib_signal,
                    %Jido.Signal{
                      type: "jido.lib.github.issue_triage.claude_probe.raw_line",
                      data: %{line: "NOT_JSON_LINE"}
                    }}
  end

  test "fails fast when prompt file cannot be written" do
    Jido.Lib.Test.FakeShellState.add_failure("/tmp/jido_claude_prompt.txt", :permission_denied)

    params = %{
      repo_dir: "/work/repo",
      session_id: "sess-123",
      issue_number: 42,
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(Claude, params, %{})
    assert result.investigation_status == :failed
    assert result.investigation_error =~ "prompt_write_failed"
  end

  test "cancels session-server command on timeout and does not fallback" do
    Process.register(self(), @cancel_probe_name)

    params = %{
      repo_dir: "/work/repo",
      session_id: "sess-timeout",
      issue_number: 42,
      timeout: 50,
      observer_pid: self(),
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent,
      shell_session_server_mod: TimeoutSessionServer
    }

    assert {:ok, result} = Jido.Exec.run(Claude, params, %{})
    assert result.investigation_status == :failed
    assert result.investigation_error =~ "timeout"

    assert_receive {:cancel_called, "sess-timeout"}

    assert_receive {:jido_lib_signal,
                    %Jido.Signal{
                      type: "jido.lib.github.issue_triage.claude_probe.mode",
                      data: %{mode: "session_server_stream"}
                    }}

    refute_receive {:jido_lib_signal,
                    %Jido.Signal{
                      type: "jido.lib.github.issue_triage.claude_probe.mode",
                      data: %{mode: "shell_agent_fallback"}
                    }}
  after
    Process.unregister(@cancel_probe_name)
  end
end
