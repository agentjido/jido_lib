defmodule Mix.Tasks.JidoLib.Github.TriageCriticTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.JidoLib.Github.TriageCritic

  test "parse_provider/2 accepts known providers" do
    assert TriageCritic.parse_provider(:claude, :writer) == :claude
    assert TriageCritic.parse_provider("codex", :critic) == :codex
  end

  test "parse_provider/2 raises for unknown provider" do
    assert_raise Mix.Error, ~r/Invalid --writer/, fn ->
      TriageCritic.parse_provider("bogus", :writer)
    end
  end

  test "normalize_max_revisions/1 allows v1 values" do
    assert TriageCritic.normalize_max_revisions(0) == 0
    assert TriageCritic.normalize_max_revisions(1) == 1
  end

  test "normalize_max_revisions/1 rejects unsupported values" do
    assert_raise Mix.Error, ~r/Allowed in v1: 0 or 1/, fn ->
      TriageCritic.normalize_max_revisions(2)
    end
  end
end
