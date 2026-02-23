defmodule Jido.Lib.Github.Actions.DocsWriter.FinalizeGuideTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Github.Actions.DocsWriter.FinalizeGuide

  test "writes final guide and manifest artifacts" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "docs-finalize-#{System.unique_integer([:positive])}")

    :ok = File.mkdir_p(tmp_dir)

    params = %{
      run_id: "run-docs-final",
      owner: "test",
      repo: "repo",
      output_repo_context: %{slug: "test/repo", alias: "primary"},
      output_path: "docs/generated/guide.md",
      publish: false,
      writer_provider: :claude,
      critic_provider: :codex,
      max_revisions: 1,
      writer_draft_v1: "Draft v1",
      writer_draft_v2: "Draft v2",
      critique_v1: %{verdict: :revise, severity: :medium, findings: []},
      critique_v2: %{verdict: :accept, severity: :low, findings: []},
      gate_v1: %{decision: :revised},
      gate_v2: %{decision: :revised},
      final_decision: :revised,
      started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      repo_dir: tmp_dir,
      workspace_dir: tmp_dir,
      session_id: "sess-123",
      sprite_config: %{},
      sprites_mod: Sprites
    }

    assert {:ok, result} = Jido.Exec.run(FinalizeGuide, params, %{})
    assert result.decision == :revised
    assert is_binary(result.final_guide)
    assert result.published == false
    assert result.artifacts.final_guide.path =~ "final_guide.md"
    assert result.artifacts.manifest.path =~ "manifest.json"
  end

  test "fails closed when decision cannot be inferred" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "docs-finalize-#{System.unique_integer([:positive])}")

    :ok = File.mkdir_p(tmp_dir)

    params = %{
      run_id: "run-docs-fail-closed",
      owner: "test",
      repo: "repo",
      writer_provider: :claude,
      critic_provider: :codex,
      max_revisions: 1,
      writer_draft_v1: "Draft v1",
      started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      repo_dir: tmp_dir,
      workspace_dir: tmp_dir,
      session_id: "sess-123",
      sprite_config: %{},
      sprites_mod: Sprites
    }

    assert {:ok, result} = Jido.Exec.run(FinalizeGuide, params, %{})
    assert result.decision == :failed
    assert result.status == :error
  end
end
