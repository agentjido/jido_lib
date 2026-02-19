defmodule Mix.Tasks.JidoLib.Github.TriageTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.JidoLib.Github.Triage

  setup_all do
    {:ok, _} = Application.ensure_all_started(:jido)

    case Jido.start([]) do
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
      "ANTHROPIC_API_KEY" => System.get_env("ANTHROPIC_API_KEY"),
      "GH_TOKEN" => System.get_env("GH_TOKEN"),
      "GITHUB_TOKEN" => System.get_env("GITHUB_TOKEN")
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

  test "parse_issue_url/1 parses github issue url" do
    assert {"agentjido", "jido", 42} =
             Triage.parse_issue_url("https://github.com/agentjido/jido/issues/42")
  end

  test "build_intake_attrs/6 builds sprite-only intake attributes" do
    attrs =
      Triage.build_intake_attrs(
        "agentjido",
        "jido",
        42,
        "https://github.com/agentjido/jido/issues/42",
        [keep_sprite: true, setup_cmd: ["mix deps.get"]],
        300_000
      )

    assert attrs.owner == "agentjido"
    assert attrs.repo == "jido"
    assert attrs.issue_number == 42
    assert attrs.keep_sprite == true
    assert attrs.setup_commands == ["mix deps.get"]
    assert attrs.sprite_config.token == "spr-token"
    assert attrs.sprite_config.env["GH_TOKEN"] == "gh-token"
  end

  test "build_feed_signal/1 builds runic.feed payload from intake map" do
    signal = Triage.build_feed_signal(%{owner: "agentjido", repo: "jido", issue_number: 42})

    assert signal.type == "runic.feed"
    assert signal.source == "/github/issue_triage_bot"
    assert signal.data.data.owner == "agentjido"
    assert signal.data.data.repo == "jido"
    assert signal.data.data.issue_number == 42
  end

  test "build_feed_signal/1 accepts map payload (for observer wiring)" do
    signal = Triage.build_feed_signal(%{owner: "agentjido", observer_pid: self()})

    assert signal.type == "runic.feed"
    assert signal.data.data.owner == "agentjido"
    assert signal.data.data.observer_pid == self()
  end
end
