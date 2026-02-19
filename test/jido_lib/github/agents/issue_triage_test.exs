defmodule Jido.Lib.Github.Agents.IssueTriageTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Agents.IssueTriageBot

  setup_all do
    {:ok, _} = Application.ensure_all_started(:jido)

    case Jido.start([]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    :ok
  end

  setup do
    Jido.Lib.Test.FakeShellState.reset!()
    :ok
  end

  test "runs sprite workflow end-to-end with direct shell session calls" do
    Jido.Lib.Test.FakeShellState.put_sprite("jido-triage-run-123")

    intake = %{
      owner: "test",
      repo: "repo",
      issue_number: 42,
      run_id: "run-123",
      setup_commands: ["mix deps.get"],
      sprite_config: %{token: "spr-token"},
      sprites_mod: Jido.Lib.Test.FakeSprites,
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent,
      shell_session_mod: Jido.Lib.Test.FakeShellSession
    }

    assert {:ok, result} = IssueTriageBot.run(intake, jido: Jido.Default, timeout: 30_000)
    assert result.status == :completed
    assert result.investigation_status == :ok
    assert result.comment_posted == true
    assert result.teardown_verified == true
    assert result.runtime_checks.gh == true

    runs = Jido.Lib.Test.FakeShellState.runs()

    mkdir_idx = command_index(runs, "mkdir -p /work/jido-triage-run-123")
    auth_idx = command_index(runs, "gh auth status")
    fetch_idx = command_index(runs, "gh issue view 42")
    clone_idx = command_index(runs, "git clone --depth 1")
    setup_idx = command_index(runs, "mix deps.get")
    validate_idx = command_index(runs, "command -v gh")
    claude_idx = command_index(runs, "claude -p")
    comment_idx = command_index(runs, "gh issue comment 42")

    assert mkdir_idx < auth_idx
    assert auth_idx < fetch_idx
    assert fetch_idx < clone_idx
    assert clone_idx < setup_idx
    assert setup_idx < validate_idx
    assert setup_idx < claude_idx
    assert validate_idx < claude_idx
    assert claude_idx < comment_idx

    assert Jido.Lib.Test.FakeShellState.stops() == ["sess-triage-run-123"]
  end

  test "preserves sprite when keep_sprite is true" do
    intake = %{
      owner: "test",
      repo: "repo",
      issue_number: 42,
      run_id: "run-keep",
      keep_sprite: true,
      sprite_config: %{token: "spr-token"},
      sprites_mod: Jido.Lib.Test.FakeSprites,
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent,
      shell_session_mod: Jido.Lib.Test.FakeShellSession
    }

    assert {:ok, result} = IssueTriageBot.run(intake, jido: Jido.Default, timeout: 30_000)

    assert result.status == :completed
    assert result.message =~ "Sprite preserved"
    assert Jido.Lib.Test.FakeShellState.stops() == []
  end

  test "cleans up sprite when workflow has failed nodes before teardown" do
    Jido.Lib.Test.FakeShellState.put_sprite("jido-triage-run-fail")
    Jido.Lib.Test.FakeShellState.add_failure("gh issue view", :api_down)

    intake = %{
      owner: "test",
      repo: "repo",
      issue_number: 42,
      run_id: "run-fail",
      sprite_config: %{token: "spr-token"},
      sprites_mod: Jido.Lib.Test.FakeSprites,
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent,
      shell_session_mod: Jido.Lib.Test.FakeShellSession
    }

    assert {:error, {:pipeline_failed, failures}} =
             IssueTriageBot.run(intake, jido: Jido.Default, timeout: 30_000)

    assert Enum.any?(failures, fn failure ->
             failure[:status] == :failed and failure[:node] == :fetch_issue
           end)

    assert Jido.Lib.Test.FakeShellState.stops() == ["sess-triage-run-fail"]
    assert Jido.Lib.Test.FakeShellState.sprite_destroys() == ["jido-triage-run-fail"]
  end

  defp command_index(runs, fragment) do
    runs
    |> Enum.find_index(fn {_sid, command} -> String.contains?(command, fragment) end)
    |> case do
      nil -> flunk("expected command containing #{inspect(fragment)}")
      index -> index
    end
  end
end
