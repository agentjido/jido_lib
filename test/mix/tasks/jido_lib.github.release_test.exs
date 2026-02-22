defmodule Mix.Tasks.JidoLib.Github.ReleaseTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.JidoLib.Github.Release

  test "parse_release_type/1 normalizes valid values" do
    assert Release.parse_release_type(nil) == :auto
    assert Release.parse_release_type("patch") == :patch
    assert Release.parse_release_type("minor") == :minor
    assert Release.parse_release_type("major") == :major
    assert Release.parse_release_type("auto") == :auto
  end

  test "parse_provider/1 defaults to codex" do
    assert Release.parse_provider(nil) == :codex
    assert Release.parse_provider("gemini") == :gemini
  end

  test "run/1 requires --yes when publish default is destructive" do
    Mix.Task.reenable("jido_lib.github.release")

    assert_raise Mix.Error, ~r/defaults to --publish true/, fn ->
      Release.run(["owner/repo"])
    end
  end
end
