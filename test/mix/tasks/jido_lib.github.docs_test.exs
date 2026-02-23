defmodule Mix.Tasks.JidoLib.Github.DocsTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.JidoLib.Github.Docs

  test "repo_specs_from_opts/1 preserves repeated --repo values and aliases" do
    opts = [repo: "agentjido/jido:primary", repo: "agentjido/jido_docs:docs"]

    assert Docs.repo_specs_from_opts(opts) == [
             "agentjido/jido:primary",
             "agentjido/jido_docs:docs"
           ]
  end

  test "read_brief_file!/1 reads brief content" do
    path = temp_brief_path("reads")
    File.write!(path, "# Docs Brief\n\nWrite a contributor guide.")
    on_exit(fn -> File.rm(path) end)

    assert Docs.read_brief_file!(path) =~ "Write a contributor guide."
  end

  test "read_brief_file!/1 raises when file is missing" do
    path = temp_brief_path("missing")

    assert_raise Mix.Error, ~r/Unable to read brief file/, fn ->
      Docs.read_brief_file!(path)
    end
  end

  test "run/1 requires --repo" do
    path = write_temp_brief!("missing-repo")
    on_exit(fn -> File.rm(path) end)

    assert_raise Mix.Error, ~r/At least one --repo owner\/repo\[:alias\] value is required/, fn ->
      Docs.run([path, "--output-repo", "primary", "--sprite-name", "docs-sprite"])
    end
  end

  test "run/1 requires --output-repo" do
    path = write_temp_brief!("missing-output-repo")
    on_exit(fn -> File.rm(path) end)

    assert_raise Mix.Error, ~r/--output-repo is required/, fn ->
      Docs.run([path, "--repo", "agentjido/jido:primary", "--sprite-name", "docs-sprite"])
    end
  end

  test "run/1 requires --sprite-name" do
    path = write_temp_brief!("missing-sprite-name")
    on_exit(fn -> File.rm(path) end)

    assert_raise Mix.Error, ~r/--sprite-name is required/, fn ->
      Docs.run([path, "--repo", "agentjido/jido:primary", "--output-repo", "primary"])
    end
  end

  test "parse_provider/3 defaults writer=codex and critic=claude" do
    assert Docs.parse_provider(nil, :writer, :codex) == :codex
    assert Docs.parse_provider(nil, :critic, :claude) == :claude
  end

  test "parse_phase/2 normalizes codex phase values" do
    assert Docs.parse_phase(nil, :triage) == :triage
    assert Docs.parse_phase("triage", :coding) == :triage
    assert Docs.parse_phase("coding", :triage) == :coding
  end

  test "parse_optional_phase/2 handles none" do
    assert Docs.parse_optional_phase(nil, :coding) == :coding
    assert Docs.parse_optional_phase("none", :coding) == nil
    assert Docs.parse_optional_phase("coding", :triage) == :coding
  end

  defp write_temp_brief!(suffix) do
    path = temp_brief_path(suffix)
    File.write!(path, "# Brief\n\nWrite docs.")
    path
  end

  defp temp_brief_path(suffix) do
    Path.join(
      System.tmp_dir!(),
      "jido-docs-brief-#{suffix}-#{System.unique_integer([:positive])}.md"
    )
  end
end
