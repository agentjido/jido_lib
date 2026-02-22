defmodule Jido.Lib.Github.Agents.IssueTriageCriticBotRunTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Agents.IssueTriageCriticBot

  setup_all do
    {:ok, _} = Application.ensure_all_started(:jido)

    case Jido.start(name: Jido.IssueTriageCriticBotRunTest) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    :ok
  end

  setup do
    Jido.Lib.Test.FakeShellState.reset!()

    previous = %{
      "SPRITES_TOKEN" => System.get_env("SPRITES_TOKEN"),
      "GH_TOKEN" => System.get_env("GH_TOKEN"),
      "ANTHROPIC_AUTH_TOKEN" => System.get_env("ANTHROPIC_AUTH_TOKEN"),
      "OPENAI_API_KEY" => System.get_env("OPENAI_API_KEY")
    }

    System.put_env("SPRITES_TOKEN", "spr-token")
    System.put_env("GH_TOKEN", "gh-token")
    System.put_env("ANTHROPIC_AUTH_TOKEN", "anthropic-token")
    System.put_env("OPENAI_API_KEY", "openai-token")

    on_exit(fn ->
      Enum.each(previous, fn {key, value} ->
        if is_nil(value), do: System.delete_env(key), else: System.put_env(key, value)
      end)
    end)

    :ok
  end

  test "runs issue triage critic workflow end-to-end" do
    run_id = "run-critic-#{System.unique_integer([:positive])}"
    Jido.Lib.Test.FakeShellState.put_sprite("jido-triage-#{run_id}")

    intake = %{
      issue_url: "https://github.com/test/repo/issues/42",
      owner: "test",
      repo: "repo",
      issue_number: 42,
      run_id: run_id,
      provider: :claude,
      writer_provider: :claude,
      critic_provider: :codex,
      max_revisions: 1,
      post_comment: false,
      timeout: 120_000,
      keep_sprite: false,
      keep_workspace: false,
      setup_commands: ["mix deps.get"],
      sprite_config: %{token: "spr-token"},
      sprites_mod: Jido.Lib.Test.FakeSprites,
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent,
      shell_session_mod: Jido.Lib.Test.FakeShellSession
    }

    assert {:ok, result} =
             IssueTriageCriticBot.run(intake,
               jido: Jido.IssueTriageCriticBotRunTest,
               timeout: 120_000,
               debug: false
             )

    assert result.status == :completed
    assert result.run_id == run_id
    assert result.writer_provider == :claude
    assert result.critic_provider == :codex
    assert result.decision in [:accepted, :revised, :rejected]
    assert is_map(result.artifacts)
    assert is_binary(result.final_comment)
  end

  test "build_intake/2 defaults providers and revision budget" do
    intake =
      IssueTriageCriticBot.build_intake("https://github.com/test/repo/issues/42",
        writer_provider: :claude,
        critic_provider: :codex,
        max_revisions: 1
      )

    assert intake.owner == "test"
    assert intake.repo == "repo"
    assert intake.issue_number == 42
    assert intake.writer_provider == :claude
    assert intake.critic_provider == :codex
    assert intake.max_revisions == 1
    assert intake.provider == :claude
  end
end
