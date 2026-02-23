defmodule Jido.Lib.Github.Actions.DocsWriter.EnsureSpriteSessionTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Actions.DocsWriter.EnsureSpriteSession

  defmodule AttachFailingSession do
    def start_with_vfs(workspace_id, opts) do
      create? =
        opts
        |> Keyword.get(:backend)
        |> elem(1)
        |> Map.get(:create)

      if create? == false do
        {:error, :sprite_not_found}
      else
        {:ok, "sess-created-#{workspace_id}"}
      end
    end
  end

  setup do
    Jido.Lib.Test.FakeShellState.reset!()
    :ok
  end

  test "attaches to sprite when initial create=false provision succeeds" do
    params = %{
      run_id: "run-docs-1",
      sprite_name: "docs-sprite",
      workspace_root: "/work/docs/docs-sprite",
      sprite_config: %{token: "spr-token"},
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent,
      shell_session_mod: Jido.Lib.Test.FakeShellSession
    }

    assert {:ok, result} = Jido.Exec.run(EnsureSpriteSession, params, %{})
    assert result.session_id == "sess-docs-run-docs-1"
    assert result.sprite_origin == :attached
    assert result.workspace_dir == "/work/docs/docs-sprite"
  end

  test "creates sprite when initial attach attempt fails" do
    params = %{
      run_id: "run-docs-1",
      sprite_name: "docs-sprite",
      workspace_root: "/work/docs/docs-sprite",
      sprite_config: %{token: "spr-token"},
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent,
      shell_session_mod: AttachFailingSession
    }

    assert {:ok, result} = Jido.Exec.run(EnsureSpriteSession, params, %{})
    assert result.session_id == "sess-created-docs-run-docs-1"
    assert result.sprite_origin == :created
  end
end
