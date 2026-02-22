defmodule Jido.Lib.Github.Actions.TriageCritic.BuildIssueBriefTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Github.Actions.TriageCritic.BuildIssueBrief

  test "writes issue brief artifact and payload" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "triage-critic-brief-#{System.unique_integer([:positive])}")

    :ok = File.mkdir_p(tmp_dir)

    params = %{
      run_id: "run-brief",
      issue_url: "https://github.com/agentjido/jido/issues/42",
      owner: "agentjido",
      repo: "jido",
      issue_number: 42,
      issue_title: "Crash on nil",
      issue_body: "Body text",
      issue_labels: ["bug"],
      writer_provider: :claude,
      critic_provider: :codex,
      max_revisions: 1,
      post_comment: true,
      repo_dir: tmp_dir,
      workspace_dir: tmp_dir,
      sprite_name: nil,
      sprite_config: %{},
      sprites_mod: Sprites
    }

    assert {:ok, result} = Jido.Exec.run(BuildIssueBrief, params, %{})
    assert is_binary(result.issue_brief)
    assert result.issue_brief =~ "Crash on nil"
    assert is_map(result.artifacts)
    assert result.artifacts.issue_brief.path =~ "issue_brief.md"
  end
end
