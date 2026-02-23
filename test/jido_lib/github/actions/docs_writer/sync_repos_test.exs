defmodule Jido.Lib.Github.Actions.DocsWriter.SyncReposTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Actions.DocsWriter.SyncRepos

  defmodule ExistingRepoShellAgent do
    def run(session_id, command, opts \\ []) do
      cond do
        String.contains?(command, "if [ -d") and String.contains?(command, ".git") ->
          {:ok, "present"}

        String.contains?(command, "remote get-url origin") ->
          {:ok, "https://github.com/test/repo.git"}

        true ->
          Jido.Lib.Test.FakeShellAgent.run(session_id, command, opts)
      end
    end

    def stop(session_id), do: Jido.Lib.Test.FakeShellAgent.stop(session_id)
  end

  setup do
    Jido.Lib.Test.FakeShellState.reset!()
    :ok
  end

  test "clones repository contexts and resolves output repo" do
    params = %{
      repos: [
        %{owner: "test", repo: "repo", slug: "test/repo", alias: "primary", rel_dir: "primary"},
        %{owner: "test", repo: "ctx", slug: "test/ctx", alias: "context", rel_dir: "context"}
      ],
      output_repo_context: %{owner: "test", repo: "repo", slug: "test/repo", alias: "primary"},
      workspace_dir: "/work/docs/docs-sprite",
      session_id: "sess-123",
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(SyncRepos, params, %{})
    assert length(result.repo_contexts) == 2
    assert result.repo_dir == "/work/docs/docs-sprite/primary"
    assert result.output_repo == "primary"

    assert Enum.any?(Jido.Lib.Test.FakeShellState.runs(), fn {_sid, cmd} ->
             String.contains?(cmd, "git clone https://github.com/test/repo.git")
           end)
  end

  test "reuses existing repo and performs fetch/checkout/pull" do
    params = %{
      repos: [
        %{owner: "test", repo: "repo", slug: "test/repo", alias: "primary", rel_dir: "primary"}
      ],
      output_repo_context: %{owner: "test", repo: "repo", slug: "test/repo", alias: "primary"},
      workspace_dir: "/work/docs/docs-sprite",
      session_id: "sess-123",
      shell_agent_mod: ExistingRepoShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(SyncRepos, params, %{})
    assert [%{sync_mode: :reused}] = result.repo_contexts

    runs = Jido.Lib.Test.FakeShellState.runs() |> Enum.map(fn {_sid, cmd} -> cmd end)
    assert Enum.any?(runs, &String.contains?(&1, "git -C"))
    assert Enum.any?(runs, &String.contains?(&1, "fetch origin"))
    assert Enum.any?(runs, &String.contains?(&1, "pull --ff-only origin"))
  end
end
