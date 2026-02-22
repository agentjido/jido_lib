defmodule Jido.Lib.Github.Actions.Roadmap.SelectWorkQueueTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Github.Actions.Roadmap.SelectWorkQueue

  test "auto includes dependencies in selected queue" do
    merged_items = [
      %{id: "ST-CORE-001", title: "Base", dependencies: []},
      %{id: "ST-CORE-002", title: "Depends", dependencies: ["ST-CORE-001"]}
    ]

    dependency_graph = %{
      nodes: Map.new(merged_items, &{&1.id, &1}),
      edges: [{"ST-CORE-002", "ST-CORE-001"}]
    }

    params = %{
      merged_items: merged_items,
      dependency_graph: dependency_graph,
      only: "ST-CORE-002",
      auto_include_dependencies: true
    }

    assert {:ok, result} = Jido.Exec.run(SelectWorkQueue, params, %{})
    ids = Enum.map(result.queue, & &1.id)

    assert "ST-CORE-002" in ids
    assert "ST-CORE-001" in ids
  end
end
