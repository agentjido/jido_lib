defmodule Jido.Lib.Github.Actions.IssueTriage.ValidateHostEnvTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Actions.IssueTriage.ValidateHostEnv

  @tracked_keys [
    "SPRITES_TOKEN",
    "ANTHROPIC_BASE_URL",
    "ANTHROPIC_AUTH_TOKEN",
    "ANTHROPIC_API_KEY",
    "CLAUDE_CODE_API_KEY",
    "GH_TOKEN",
    "GITHUB_TOKEN",
    "ANTHROPIC_DEFAULT_SONNET_MODEL"
  ]

  setup do
    previous =
      @tracked_keys
      |> Enum.map(&{&1, System.get_env(&1)})
      |> Enum.into(%{})

    on_exit(fn ->
      Enum.each(previous, fn {key, value} ->
        if is_binary(value), do: System.put_env(key, value), else: System.delete_env(key)
      end)
    end)

    :ok
  end

  test "validate_host_env!/0 passes for strict ZAI requirements" do
    System.put_env("SPRITES_TOKEN", "spr-token")
    System.put_env("ANTHROPIC_BASE_URL", "https://zai.example/v1")
    System.put_env("ANTHROPIC_AUTH_TOKEN", "auth-token")
    System.put_env("GH_TOKEN", "gh-token")

    assert :ok == ValidateHostEnv.validate_host_env!()
  end

  test "validate_host_env!/0 fails when base url is missing" do
    System.put_env("SPRITES_TOKEN", "spr-token")
    System.delete_env("ANTHROPIC_BASE_URL")
    System.put_env("ANTHROPIC_API_KEY", "api-key")
    System.put_env("GH_TOKEN", "gh-token")

    assert_raise RuntimeError, ~r/ANTHROPIC_BASE_URL/, fn ->
      ValidateHostEnv.validate_host_env!()
    end
  end

  test "build_sprite_env/0 forwards auth, model, and github vars" do
    System.put_env("ANTHROPIC_BASE_URL", "https://zai.example/v1")
    System.put_env("CLAUDE_CODE_API_KEY", "claude-key")
    System.put_env("ANTHROPIC_DEFAULT_SONNET_MODEL", "claude-sonnet-x")
    System.put_env("GITHUB_TOKEN", "ghp_test")

    env = ValidateHostEnv.build_sprite_env()

    assert env["ANTHROPIC_BASE_URL"] == "https://zai.example/v1"
    assert env["CLAUDE_CODE_API_KEY"] == "claude-key"
    assert env["ANTHROPIC_DEFAULT_SONNET_MODEL"] == "claude-sonnet-x"
    assert env["GITHUB_TOKEN"] == "ghp_test"
    assert env["GH_PROMPT_DISABLED"] == "1"
    assert env["GIT_TERMINAL_PROMPT"] == "0"
  end

  test "run/2 validates env and passes through intake fields" do
    System.put_env("SPRITES_TOKEN", "spr-token")
    System.put_env("ANTHROPIC_BASE_URL", "https://zai.example/v1")
    System.put_env("ANTHROPIC_AUTH_TOKEN", "auth-token")
    System.put_env("GH_TOKEN", "gh-token")

    params = %{
      run_id: "run-123",
      owner: "agentjido",
      repo: "jido_chat",
      issue_number: 19,
      issue_url: "https://github.com/agentjido/jido_chat/issues/19",
      timeout: 300_000,
      keep_workspace: false,
      keep_sprite: false,
      setup_commands: ["mix deps.get"],
      prompt: nil,
      observer_pid: self(),
      sprite_config: %{token: "spr-token"},
      sprites_mod: Jido.Lib.Test.FakeSprites,
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent,
      shell_session_mod: Jido.Lib.Test.FakeShellSession
    }

    assert {:ok, result} = Jido.Exec.run(ValidateHostEnv, params, %{})
    assert result.run_id == "run-123"
    assert result.owner == "agentjido"
    assert result.issue_number == 19
    assert result.observer_pid == self()
  end
end
