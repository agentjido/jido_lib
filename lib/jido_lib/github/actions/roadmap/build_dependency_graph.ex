defmodule Jido.Lib.Github.Actions.Roadmap.BuildDependencyGraph do
  @moduledoc """
  Builds dependency graph metadata for merged roadmap items.
  """

  use Jido.Action,
    name: "roadmap_build_dependency_graph",
    description: "Build roadmap dependency graph",
    compensation: [max_retries: 0],
    schema: [
      merged_items: [type: {:list, :map}, default: []],
      auto_include_dependencies: [type: :boolean, default: true]
    ]

  alias Jido.Lib.Github.Actions.Roadmap.Helpers

  @impl true
  def run(params, _context) do
    nodes = Map.new(params[:merged_items], &{&1.id, &1})

    edges =
      params[:merged_items]
      |> Enum.flat_map(fn item ->
        deps = item[:dependencies] || []
        Enum.map(deps, &{item.id, &1})
      end)

    graph = %{
      nodes: nodes,
      edges: edges,
      auto_include_dependencies: params[:auto_include_dependencies] == true
    }

    {:ok, Helpers.pass_through(params) |> Map.put(:dependency_graph, graph)}
  end
end
