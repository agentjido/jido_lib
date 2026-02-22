defmodule Jido.Lib.Bots.Foundation.ArtifactStoreTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Bots.Foundation.ArtifactStore

  test "writes and reads text/json artifacts with local fallback" do
    tmp_root =
      Path.join(System.tmp_dir!(), "artifact-store-#{System.unique_integer([:positive])}")

    :ok = File.mkdir_p(tmp_root)

    assert {:ok, store} = ArtifactStore.new(run_id: "run-123", local_prefix: tmp_root)

    assert {:ok, meta} = ArtifactStore.write_text(store, "issue_brief.md", "hello")
    assert meta.path =~ ".jido/runs/run-123/issue_brief.md"

    assert {:ok, "hello"} = ArtifactStore.read_text(store, "issue_brief.md")

    assert {:ok, _json_meta} = ArtifactStore.write_json(store, "manifest.json", %{status: "ok"})
    assert {:ok, decoded} = ArtifactStore.read_json(store, "manifest.json")
    assert decoded["status"] == "ok"
  end
end
