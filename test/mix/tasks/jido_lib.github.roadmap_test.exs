defmodule Mix.Tasks.JidoLib.Github.RoadmapTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.JidoLib.Github.Roadmap

  test "normalize_stories_dirs/1 falls back to default" do
    assert Roadmap.normalize_stories_dirs([]) == ["specs/stories"]
  end

  test "normalize_stories_dirs/1 keeps multiple --stories-dir values" do
    dirs =
      Roadmap.normalize_stories_dirs(
        stories_dir: "specs/stories",
        stories_dir: "backlog"
      )

    assert dirs == ["specs/stories", "backlog"]
  end

  test "parse_provider/1 defaults to codex" do
    assert Roadmap.parse_provider(nil) == :codex
    assert Roadmap.parse_provider("amp") == :amp
  end

  test "run/1 requires --yes when mutation defaults are enabled" do
    Mix.Task.reenable("jido_lib.github.roadmap")

    assert_raise Mix.Error, ~r/defaults to --apply\/--push\/--open-pr true/, fn ->
      Roadmap.run(["."])
    end
  end
end
