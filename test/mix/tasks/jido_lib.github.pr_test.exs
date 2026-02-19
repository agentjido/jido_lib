defmodule Mix.Tasks.JidoLib.Github.PrTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.JidoLib.Github.Pr

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

  test "parse_issue_url/1 parses github issue URL" do
    assert {"agentjido", "jido_chat", 19} =
             Pr.parse_issue_url("https://github.com/agentjido/jido_chat/issues/19")
  end

  test "build_intake/2 builds payload with PR defaults" do
    intake =
      Pr.build_intake(
        "https://github.com/agentjido/jido_chat/issues/19",
        keep_sprite: true,
        setup_commands: ["mix deps.get"],
        check_commands: ["mix test --exclude integration"],
        timeout: 900_000
      )

    assert intake.owner == "agentjido"
    assert intake.repo == "jido_chat"
    assert intake.issue_number == 19
    assert intake.keep_sprite == true
    assert intake.setup_commands == ["mix deps.get"]
    assert intake.check_commands == ["mix test --exclude integration"]
    assert intake.sprite_config.token == "spr-token"
    assert intake.branch_prefix == "jido/prbot"
  end

  test "build_feed_signal/1 builds runic.feed signal from payload" do
    signal = Pr.build_feed_signal(%{owner: "agentjido", repo: "jido_chat", issue_number: 19})

    assert signal.type == "runic.feed"
    assert signal.source == "/github/pr_bot"
    assert signal.data.data.owner == "agentjido"
    assert signal.data.data.repo == "jido_chat"
    assert signal.data.data.issue_number == 19
  end
end
