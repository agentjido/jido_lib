defmodule Jido.Lib.Github.Actions.IssueTriage.ProvisionSpriteTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Actions.IssueTriage.ProvisionSprite

  setup do
    Jido.Lib.Test.FakeShellState.reset!()
    :ok
  end

  test "provisions session and creates workspace" do
    params = %{
      run_id: "run-123",
      owner: "agentjido",
      repo: "jido",
      issue_number: 42,
      sprite_config: %{
        token: "spr-token",
        create: true,
        env: %{"GH_TOKEN" => "gh-token"}
      },
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent,
      shell_session_mod: Jido.Lib.Test.FakeShellSession
    }

    assert {:ok, result} = Jido.Exec.run(ProvisionSprite, params, %{})

    assert result.session_id == "sess-triage-run-123"
    assert result.workspace_dir == "/work/jido-triage-run-123"
    assert result.sprite_name == "jido-triage-run-123"
    assert result.sprites_mod == Sprites

    assert Enum.any?(Jido.Lib.Test.FakeShellState.runs(), fn {_sid, cmd} ->
             String.contains?(cmd, "mkdir -p /work/jido-triage-run-123")
           end)
  end
end
