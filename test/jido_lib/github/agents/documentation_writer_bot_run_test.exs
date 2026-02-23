defmodule Jido.Lib.Github.Agents.DocumentationWriterBotRunTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Agents.DocumentationWriterBot

  setup_all do
    {:ok, _} = Application.ensure_all_started(:jido)

    case Jido.start(name: Jido.DocumentationWriterBotRunTest) do
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

  test "runs documentation writer workflow end-to-end" do
    run_id = "run-docs-#{System.unique_integer([:positive])}"
    sprite_name = "docs-sprite-#{run_id}"

    Jido.Lib.Test.FakeShellState.put_sprite(sprite_name)

    intake = %{
      run_id: run_id,
      brief: "Write a contributor guide using primary and context repos.",
      repos: ["test/repo:primary", "test/context:context"],
      output_repo: "primary",
      output_path: nil,
      publish: false,
      writer_provider: :claude,
      critic_provider: :codex,
      max_revisions: 1,
      sprite_name: sprite_name,
      workspace_root: "/work/docs/#{sprite_name}",
      timeout: 120_000,
      keep_sprite: false,
      setup_commands: ["mix deps.get"],
      sprite_config: %{token: "spr-token"},
      sprites_mod: Jido.Lib.Test.FakeSprites,
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent,
      shell_session_mod: Jido.Lib.Test.FakeShellSession,
      shell_session_server_mod: Jido.Shell.ShellSessionServer
    }

    assert {:ok, result} =
             DocumentationWriterBot.run(intake,
               jido: Jido.DocumentationWriterBotRunTest,
               timeout: 120_000,
               debug: false
             )

    assert result.status == :completed
    assert result.run_id == run_id
    assert result.writer_provider == :claude
    assert result.critic_provider == :codex
    assert result.decision in [:accepted, :revised, :rejected]
    assert is_binary(result.final_guide)
    assert is_list(result.repo_contexts)
    assert result.published == false
  end

  test "build_intake/2 defaults providers and revision budget" do
    intake =
      DocumentationWriterBot.build_intake("Write docs",
        repos: ["test/repo:primary"],
        output_repo: "primary",
        sprite_name: "docs-sprite",
        max_revisions: 1
      )

    assert intake.writer_provider == :codex
    assert intake.critic_provider == :claude
    assert intake.max_revisions == 1
    assert intake.keep_sprite == true
  end
end
