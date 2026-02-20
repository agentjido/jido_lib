defmodule Jido.Lib.Github.Agents.PrBotIntakeTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Agents.PrBot

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

    on_exit(fn ->
      Enum.each(previous, fn {key, val} ->
        if is_nil(val), do: System.delete_env(key), else: System.put_env(key, val)
      end)
    end)

    :ok
  end

  test "parse_issue_url/1 parses valid github issue URL" do
    assert {"agentjido", "jido_chat", 19} =
             PrBot.parse_issue_url("https://github.com/agentjido/jido_chat/issues/19")
  end

  test "build_intake/2 builds canonical payload with defaults" do
    intake =
      PrBot.build_intake(
        "https://github.com/agentjido/jido_chat/issues/19",
        keep_sprite: true,
        setup_commands: ["mix deps.get"],
        check_commands: ["mix test --exclude integration"],
        timeout: 900_000
      )

    assert intake.owner == "agentjido"
    assert intake.repo == "jido_chat"
    assert intake.issue_number == 19
    assert intake.provider == :claude
    assert intake.keep_sprite == true
    assert intake.setup_commands == ["mix deps.get"]
    assert intake.check_commands == ["mix test --exclude integration"]
    assert intake.branch_prefix == "jido/prbot"
    assert intake.sprite_config.token == "spr-token"
  end

  test "build_intake/2 accepts provider override" do
    intake =
      PrBot.build_intake(
        "https://github.com/agentjido/jido_chat/issues/19",
        provider: :gemini
      )

    assert intake.provider == :gemini
  end

  test "intake_signal/1 wraps payload in runic.feed signal" do
    signal =
      PrBot.intake_signal(%{
        issue_url: "https://github.com/agentjido/jido_chat/issues/19",
        run_id: "run-123"
      })

    assert signal.type == "runic.feed"
    assert signal.source == "/github/pr_bot"
    assert signal.data.data.run_id == "run-123"
  end
end
