defmodule Mix.Tasks.JidoLib.Github.QualityTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.JidoLib.Github.Quality

  test "build_publish_comment/1 returns nil without both repo and issue" do
    assert Quality.build_publish_comment([]) == nil
    assert Quality.build_publish_comment(publish_repo: "agentjido/jido_lib") == nil
    assert Quality.build_publish_comment(publish_issue: 12) == nil
  end

  test "build_publish_comment/1 builds comment target with repo and issue number" do
    assert Quality.build_publish_comment(publish_repo: "agentjido/jido_lib", publish_issue: 12) ==
             %{
               repo: "agentjido/jido_lib",
               issue_number: 12
             }
  end

  test "parse_provider/1 defaults to codex" do
    assert Quality.parse_provider(nil) == :codex
    assert Quality.parse_provider("codex") == :codex
  end

  test "run/1 requires --yes when apply default is destructive" do
    Mix.Task.reenable("jido_lib.github.quality")

    assert_raise Mix.Error, ~r/defaults to --apply true/, fn ->
      Quality.run(["."])
    end
  end

  test "run/1 allows report-only mode without --yes" do
    Mix.Task.reenable("jido_lib.github.quality")

    assert is_map(Quality.run([".", "--no-apply"]))
  end
end
