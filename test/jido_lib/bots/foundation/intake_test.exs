defmodule Jido.Lib.Bots.Foundation.IntakeTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Bots.Foundation.Intake

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

  test "normalize_run_id/1 preserves non-empty values and generates default ids" do
    assert Intake.normalize_run_id("run-123") == "run-123"

    generated = Intake.normalize_run_id(nil)
    assert generated =~ ~r/^[a-f0-9]{12}$/
  end

  test "normalize_provider/2 falls back on invalid providers" do
    assert Intake.normalize_provider(:codex, :codex) == :codex
    assert Intake.normalize_provider("bogus", :codex) == :codex
  end

  test "normalize_provider!/2 raises on invalid providers" do
    assert Intake.normalize_provider!(:claude, :codex) == :claude

    assert_raise ArgumentError, ~r/Invalid provider/, fn ->
      Intake.normalize_provider!("bogus", :codex)
    end
  end

  test "normalize_commands/1 canonicalizes scalar and repeated values" do
    assert Intake.normalize_commands("mix deps.get") == ["mix deps.get"]

    assert Intake.normalize_commands(["mix deps.get", "mix compile"]) == [
             "mix deps.get",
             "mix compile"
           ]

    assert Intake.normalize_commands([nil, " ", "mix test"]) == ["mix test"]
  end

  test "build_sprite_config/2 merges defaults for multiple providers" do
    System.put_env("SPRITES_TOKEN", "spr-token")
    System.put_env("GH_TOKEN", "gh-token")
    System.put_env("CLAUDE_CODE_API_KEY", "claude-key")
    System.put_env("OPENAI_API_KEY", "openai-key")

    config =
      Intake.build_sprite_config([:claude, :codex], %{
        env: %{"CUSTOM_ENV" => "1"}
      })

    assert config.token == "spr-token"
    assert config.create == true
    assert config.env["GH_TOKEN"] == "gh-token"
    assert config.env["CLAUDE_CODE_API_KEY"] == "claude-key"
    assert config.env["OPENAI_API_KEY"] == "openai-key"
    assert config.env["CUSTOM_ENV"] == "1"
  end
end
