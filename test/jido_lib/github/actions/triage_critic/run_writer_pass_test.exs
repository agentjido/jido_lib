defmodule Jido.Lib.Github.Actions.TriageCritic.RunWriterPassTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Actions.TriageCritic.RunWriterPass

  setup do
    Jido.Lib.Test.FakeShellState.reset!()
    :ok
  end

  test "runs writer pass v1 and persists draft" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "triage-critic-writer-#{System.unique_integer([:positive])}")

    :ok = File.mkdir_p(tmp_dir)

    params = %{
      iteration: 1,
      run_id: "run-writer",
      session_id: "sess-123",
      repo_dir: tmp_dir,
      issue_number: 42,
      issue_url: "https://github.com/agentjido/jido/issues/42",
      issue_title: "Crash on nil",
      issue_body: "Body text",
      issue_labels: ["bug"],
      issue_brief: "Brief",
      writer_provider: :claude,
      critic_provider: :codex,
      role_runtime_ready: %{claude: true, codex: true},
      timeout: 60_000,
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent,
      repo: "jido",
      owner: "agentjido",
      workspace_dir: tmp_dir,
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
      run_id: "run-skip",
      session_id: "sess-123",
      repo_dir: "/tmp",
      issue_number: 42,
      issue_url: "https://github.com/agentjido/jido/issues/42",
      writer_provider: :claude,
      critic_provider: :codex,
      needs_revision: false,
      role_runtime_ready: %{claude: true, codex: true},
      repo: "jido",
      owner: "agentjido"
    }

    assert {:ok, result} = Jido.Exec.run(RunWriterPass, params, %{})
    refute Map.has_key?(result, :writer_draft_v2)
  end
end
