defmodule Jido.Lib.Github.Actions.TriageCritic.PrepareRoleRuntimesTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Actions.TriageCritic.PrepareRoleRuntimes

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

  test "bootstraps both providers and marks runtime ready" do
    params = %{
      writer_provider: :claude,
      critic_provider: :codex,
      session_id: "sess-123",
      repo_dir: "/work/repo",
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(PrepareRoleRuntimes, params, %{})
    assert result.role_runtime_ready.claude == true
    assert result.role_runtime_ready.codex == true
    assert is_map(result.role_runtime)
  end
end
