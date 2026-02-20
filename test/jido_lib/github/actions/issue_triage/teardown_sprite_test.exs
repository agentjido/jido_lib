defmodule Jido.Lib.Github.Actions.TeardownSpriteTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Actions.TeardownSprite

  defmodule AlwaysPresentSprites do
    def new(_token, _opts \\ []), do: %{client: :ok}
    def sprite(client, name), do: %{client: client, name: name}
    def get_sprite(_client, _name), do: {:ok, %{"status" => "tracked"}}
    def destroy(_sprite), do: {:error, :api_down}
  end

  setup do
    Jido.Lib.Test.FakeShellState.reset!()
    :ok
  end

  test "stops session and verifies sprite teardown" do
    Jido.Lib.Test.FakeShellState.put_sprite("sprite-123")

    params = %{
      run_id: "run-123",
      session_id: "sess-123",
      workspace_dir: "/work/jido-triage-run-123",
      keep_sprite: false,
      sprite_name: "sprite-123",
      sprite_config: %{token: "spr-token"},
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent,
      sprites_mod: Jido.Lib.Test.FakeSprites
    }

    assert {:ok, result} = Jido.Exec.run(TeardownSprite, params, %{})
    assert result.status == :completed
    assert result.message == "Sprite destroyed (verified)"
    assert result.teardown_verified == true
    assert result.teardown_attempts == 1
    assert Jido.Lib.Test.FakeShellState.stops() == ["sess-123"]
    assert Jido.Lib.Test.FakeShellState.sprite_destroys() == ["sprite-123"]
  end

  test "warns when teardown cannot be verified after retries" do
    params = %{
      run_id: "run-123",
      session_id: "sess-123",
      workspace_dir: "/work/jido-triage-run-123",
      keep_sprite: false,
      sprite_name: "sprite-123",
      sprite_config: %{token: "spr-token"},
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent,
      sprites_mod: AlwaysPresentSprites
    }

    assert {:ok, result} = Jido.Exec.run(TeardownSprite, params, %{})
    assert result.status == :completed
    assert result.message == "Sprite teardown not verified after retries"
    assert result.teardown_verified == false
    assert result.teardown_attempts == 3
    assert is_list(result.warnings)
    assert Enum.any?(result.warnings, &String.contains?(&1, "sprite teardown not verified"))
    assert length(Jido.Lib.Test.FakeShellState.stops()) == 3
  end

  test "preserves sprite session when keep_sprite is true" do
    params = %{
      run_id: "run-123",
      session_id: "sess-123",
      workspace_dir: "/work/jido-triage-run-123",
      keep_sprite: true,
      sprite_name: "sprite-123",
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(TeardownSprite, params, %{})
    assert result.status == :completed
    assert result.message =~ "Sprite preserved"
    assert result.teardown_verified == nil
    assert result.teardown_attempts == nil
    assert Jido.Lib.Test.FakeShellState.stops() == []
  end
end
