defmodule Jido.Lib.Bots.Foundation.RunContextTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Bots.Foundation.RunContext

  @tracked_env_keys ["SPRITES_TOKEN", "GH_TOKEN", "CLAUDE_CODE_API_KEY", "OPENAI_API_KEY"]

  setup do
    previous =
      @tracked_env_keys
      |> Enum.map(&{&1, System.get_env(&1)})
      |> Enum.into(%{})

    on_exit(fn ->
      Enum.each(previous, fn {key, value} ->
        if is_binary(value), do: System.put_env(key, value), else: System.delete_env(key)
      end)
    end)

    :ok
  end

  test "from_issue_url/2 normalizes providers and defaults" do
    assert {:ok, context} =
             RunContext.from_issue_url("https://github.com/agentjido/jido/issues/42",
               writer_provider: "claude",
               critic_provider: :codex,
               max_revisions: 1,
               setup_commands: ["mix deps.get"]
             )

    assert context.owner == "agentjido"
    assert context.repo == "jido"
    assert context.issue_number == 42
    assert context.writer_provider == :claude
    assert context.critic_provider == :codex
    assert context.max_revisions == 1
    assert context.setup_commands == ["mix deps.get"]

    intake = RunContext.to_intake(context)
    assert intake.provider == :claude
    assert intake.writer_provider == :claude
    assert intake.critic_provider == :codex
  end

  test "default sprite env merges writer and critic provider vars" do
    System.put_env("SPRITES_TOKEN", "spr-token")
    System.put_env("GH_TOKEN", "gh-token")
    System.put_env("CLAUDE_CODE_API_KEY", "claude-key")
    System.put_env("OPENAI_API_KEY", "openai-key")

    assert {:ok, context} =
             RunContext.from_issue_url("https://github.com/agentjido/jido/issues/42",
               writer_provider: :claude,
               critic_provider: :codex
             )

    assert context.sprite_config.token == "spr-token"
    assert context.sprite_config.env["GH_TOKEN"] == "gh-token"
    assert context.sprite_config.env["CLAUDE_CODE_API_KEY"] == "claude-key"
    assert context.sprite_config.env["OPENAI_API_KEY"] == "openai-key"
  end

  test "new/1 rejects unsupported revision budgets" do
    assert {:error, %ArgumentError{}} =
             RunContext.new(%{
               issue_url: "https://github.com/agentjido/jido/issues/42",
               writer_provider: :claude,
               critic_provider: :codex,
               max_revisions: 3
             })
  end
end
