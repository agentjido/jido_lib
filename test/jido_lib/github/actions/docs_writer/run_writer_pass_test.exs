defmodule Jido.Lib.Github.Actions.DocsWriter.RunWriterPassTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Actions.DocsWriter.RunWriterPass

  defmodule StatusThenCatShellAgent do
    def run(_session_id, command, _opts \\ []) when is_binary(command) do
      cond do
        String.contains?(command, "cat >") ->
          {:ok, "ok"}

        String.contains?(command, "codex exec") ->
          {:ok,
           [
             Jason.encode!(%{"type" => "thread.started", "thread_id" => "thread-1"}),
             Jason.encode!(%{"type" => "turn.started"}),
             Jason.encode!(%{
               "type" => "item.completed",
               "item" => %{
                 "type" => "agent_message",
                 "text" =>
                   "Updated the guide at `priv/pages/docs/learn/agent-fundamentals.md` to meet the brief.\n\nNo tests were run."
               }
             }),
             Jason.encode!(%{"type" => "turn.completed", "usage" => %{"output_tokens" => 3}})
           ]
           |> Enum.join("\n")}

        String.contains?(command, "cat") and
            String.contains?(command, "docs/generated/guide.md") ->
          {:ok, "# Guide\n\nRendered from repo file.\n"}

        true ->
          {:ok, "ok"}
      end
    end
  end

  setup do
    Jido.Lib.Test.FakeShellState.reset!()
    :ok
  end

  test "runs writer pass v1 and persists draft" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "docs-writer-pass-#{System.unique_integer([:positive])}")

    :ok = File.mkdir_p(tmp_dir)

    params = %{
      iteration: 1,
      run_id: "run-docs-writer",
      session_id: "sess-123",
      repo_dir: tmp_dir,
      docs_brief: "Brief",
      writer_provider: :claude,
      critic_provider: :codex,
      role_runtime_ready: %{claude: true, codex: true},
      timeout: 60_000,
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent,
      repo: "repo",
      owner: "test",
      workspace_dir: tmp_dir,
      output_repo_context: %{slug: "test/repo"},
      output_path: "docs/generated/guide.md",
      sprite_config: %{},
      sprites_mod: Sprites
    }

    assert {:ok, result} = Jido.Exec.run(RunWriterPass, params, %{})
    assert is_binary(result.writer_draft_v1)
    assert result.writer_draft_v1 =~ "Investigation"
    assert result.artifacts.writer_draft_v1.path =~ "writer_draft_v1.md"
  end

  test "skips v2 when revision gate is not active" do
    params = %{
      iteration: 2,
      run_id: "run-docs-skip",
      session_id: "sess-123",
      repo_dir: "/tmp",
      docs_brief: "Brief",
      writer_provider: :claude,
      critic_provider: :codex,
      needs_revision: false,
      role_runtime_ready: %{claude: true, codex: true},
      repo: "repo",
      owner: "test"
    }

    assert {:ok, result} = Jido.Exec.run(RunWriterPass, params, %{})
    refute Map.has_key?(result, :writer_draft_v2)
  end

  test "uses generated repo file when codex returns status summary instead of guide body" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "docs-writer-codex-#{System.unique_integer([:positive])}")

    :ok = File.mkdir_p(tmp_dir)

    params = %{
      iteration: 1,
      run_id: "run-docs-codex-status",
      session_id: "sess-456",
      repo_dir: tmp_dir,
      docs_brief: "Brief",
      writer_provider: :codex,
      critic_provider: :codex,
      role_runtime_ready: %{codex: true},
      timeout: 60_000,
      shell_agent_mod: StatusThenCatShellAgent,
      repo: "repo",
      owner: "test",
      workspace_dir: tmp_dir,
      output_repo_context: %{slug: "test/repo"},
      output_path: "docs/generated/guide.md",
      sprite_config: %{},
      sprites_mod: Sprites
    }

    assert {:ok, result} = Jido.Exec.run(RunWriterPass, params, %{})
    assert String.trim(result.writer_draft_v1) == "# Guide\n\nRendered from repo file."
  end
end
