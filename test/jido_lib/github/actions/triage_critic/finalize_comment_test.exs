defmodule Jido.Lib.Github.Actions.TriageCritic.FinalizeCommentTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Github.Actions.TriageCritic.FinalizeComment

  test "writes final comment and manifest artifacts without posting" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "triage-critic-final-#{System.unique_integer([:positive])}")

    :ok = File.mkdir_p(tmp_dir)

    params = %{
      run_id: "run-final",
      issue_url: "https://github.com/agentjido/jido/issues/42",
      owner: "agentjido",
      repo: "jido",
      issue_number: 42,
      writer_provider: :claude,
      critic_provider: :codex,
      post_comment: false,
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

    assert {:ok, result} = Jido.Exec.run(FinalizeComment, params, %{})
    assert result.decision == :revised
    assert result.comment_posted == false
    assert is_binary(result.final_comment)
    assert result.artifacts.final_comment.path =~ "final_comment.md"
    assert result.artifacts.manifest.path =~ "manifest.json"
  end
end
