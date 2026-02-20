defmodule Jido.Lib.Github.Agents.PrBotRunTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Agents.PrBot

  setup_all do
    {:ok, _} = Application.ensure_all_started(:jido)

    case Jido.start(name: Jido.PrBotRunTest) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    :ok
  end

  setup do
    previous = %{
      "SPRITES_TOKEN" => System.get_env("SPRITES_TOKEN"),
      "ANTHROPIC_BASE_URL" => System.get_env("ANTHROPIC_BASE_URL"),
      "ANTHROPIC_AUTH_TOKEN" => System.get_env("ANTHROPIC_AUTH_TOKEN"),
      "GH_TOKEN" => System.get_env("GH_TOKEN")
    }

    System.put_env("SPRITES_TOKEN", "spr-token")
    System.put_env("ANTHROPIC_BASE_URL", "https://zai.example/v1")
    System.put_env("ANTHROPIC_AUTH_TOKEN", "anthropic-token")
    System.put_env("GH_TOKEN", "gh-token")

    Jido.Lib.Test.FakeShellState.reset!()

    on_exit(fn ->
      Enum.each(previous, fn {key, val} ->
        if is_nil(val), do: System.delete_env(key), else: System.put_env(key, val)
      end)
    end)

    :ok
  end

  test "runs PR workflow end-to-end and returns PR metadata" do
    Jido.Lib.Test.FakeShellState.put_sprite("jido-triage-run-123")

    intake = %{
      issue_url: "https://github.com/test/repo/issues/42",
      owner: "test",
      repo: "repo",
      issue_number: 42,
      run_id: "run-123",
      setup_commands: ["mix deps.get"],
      check_commands: ["mix deps.get", "mix compile"],
      sprite_config: %{token: "spr-token"},
      sprites_mod: Jido.Lib.Test.FakeSprites,
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent,
      shell_session_mod: Jido.Lib.Test.FakeShellSession
    }

    assert {:ok, result} = PrBot.run(intake, jido: Jido.PrBotRunTest, timeout: 60_000)
    assert result.provider == :claude
    assert result.agent_status == :ok
    assert result.pr_created == true
    assert result.pr_url == "https://github.com/test/repo/pull/7"
    assert result.issue_comment_posted == true
    assert result.teardown_verified == true

    runs = Jido.Lib.Test.FakeShellState.runs()

    setup_git_idx = command_index(runs, "gh auth setup-git")
    branch_idx = command_index(runs, "git checkout -b jido/prbot/issue-42-run-123")
    claude_idx = command_index(runs, "claude -p")
    checks_idx = command_index(runs, "&& mix compile")
    push_idx = command_index(runs, "git push -u origin jido/prbot/issue-42-run-123")
    pr_idx = command_index(runs, "gh pr create")
    comment_idx = command_index(runs, "gh issue comment 42")

    assert setup_git_idx < branch_idx
    assert branch_idx < claude_idx
    assert claude_idx < checks_idx
    assert checks_idx < push_idx
    assert push_idx < pr_idx
    assert pr_idx < comment_idx

    assert Jido.Lib.Test.FakeShellState.stops() == ["sess-triage-run-123"]
  end

  test "cleans up sprite when workflow fails before teardown node" do
    Jido.Lib.Test.FakeShellState.put_sprite("jido-triage-run-fail")
    Jido.Lib.Test.FakeShellState.add_failure("git rev-list --count", :command_failed)

    intake = %{
      issue_url: "https://github.com/test/repo/issues/42",
      owner: "test",
      repo: "repo",
      issue_number: 42,
      run_id: "run-fail",
      setup_commands: ["mix deps.get"],
      check_commands: ["mix deps.get"],
      sprite_config: %{token: "spr-token"},
      sprites_mod: Jido.Lib.Test.FakeSprites,
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent,
      shell_session_mod: Jido.Lib.Test.FakeShellSession
    }

    assert {:error, {:pipeline_failed, failures}, _partial} =
             PrBot.run(intake, jido: Jido.PrBotRunTest, timeout: 60_000)

    assert Enum.any?(failures, fn failure ->
             failure[:status] == :failed and failure[:node] == :ensure_commit
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
