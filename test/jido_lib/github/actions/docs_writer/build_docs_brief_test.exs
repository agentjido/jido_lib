defmodule Jido.Lib.Github.Actions.DocsWriter.BuildDocsBriefTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Actions.DocsWriter.BuildDocsBrief

  test "writes docs brief artifact" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "docs-writer-brief-#{System.unique_integer([:positive])}")

    :ok = File.mkdir_p(tmp_dir)

    params = %{
      run_id: "run-docs-brief",
      brief: "Write a setup guide for contributors.",
      repos: [%{slug: "test/repo", alias: "primary"}],
      output_repo_context: %{slug: "test/repo"},
      output_path: "docs/generated/setup.md",
      publish: true,
      writer_provider: :codex,
      critic_provider: :claude,
      max_revisions: 1,
      repo_dir: tmp_dir,
      workspace_dir: tmp_dir,
      sprite_config: %{},
      sprites_mod: Sprites
    }

    assert {:ok, result} = Jido.Exec.run(BuildDocsBrief, params, %{})
    assert is_binary(result.docs_brief)
    assert result.docs_brief =~ "Documentation Guide Brief"
    assert result.artifacts.docs_brief.path =~ "docs_brief.md"
  end
end
