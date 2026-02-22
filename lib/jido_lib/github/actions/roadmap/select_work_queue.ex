defmodule Jido.Lib.Github.Actions.Roadmap.SelectWorkQueue do
  @moduledoc """
  Selects ordered roadmap queue with filter options.
  """

  use Jido.Action,
    name: "roadmap_select_work_queue",
    description: "Select roadmap work queue",
    compensation: [max_retries: 0],
    schema: [
      merged_items: [type: {:list, :map}, default: []],
      dependency_graph: [type: {:or, [:map, nil]}, default: nil],
      max_items: [type: {:or, [:integer, nil]}, default: nil],
      start_at: [type: {:or, [:string, nil]}, default: nil],
      end_at: [type: {:or, [:string, nil]}, default: nil],
      only: [type: {:or, [:string, nil]}, default: nil],
      include_completed: [type: :boolean, default: false],
      auto_include_dependencies: [type: :boolean, default: true]
    ]

  alias Jido.Lib.Github.Actions.Roadmap.Helpers

  @impl true
  def run(params, _context) do
    base_queue =
      params[:merged_items]
      |> Enum.sort_by(& &1.id)
      |> filter_only(params[:only])
      |> filter_range(params[:start_at], params[:end_at])
      |> maybe_limit(params[:max_items])

    queue =
      if params[:auto_include_dependencies] == true do
        include_dependencies(base_queue, params[:dependency_graph], params[:merged_items])
      else
        base_queue
      end

    {:ok, Helpers.pass_through(params) |> Map.put(:queue, queue)}
  end

  defp filter_only(items, nil), do: items
  defp filter_only(items, only), do: Enum.filter(items, &(&1.id == only))

  defp filter_range(items, nil, nil), do: items

  defp filter_range(items, start_at, end_at) do
    Enum.filter(items, fn item ->
      after_start = is_nil(start_at) or item.id >= start_at
      before_end = is_nil(end_at) or item.id <= end_at
      after_start and before_end
    end)
  end

  defp maybe_limit(items, max) when is_integer(max) and max > 0, do: Enum.take(items, max)
  defp maybe_limit(items, _max), do: items

  defp include_dependencies(queue, %{} = graph, merged_items) when is_list(merged_items) do
    node_map = Map.get(graph, :nodes, %{})
    merged_map = Map.new(merged_items, &{&1.id, &1})
    queue_ids = MapSet.new(Enum.map(queue, & &1.id))

    queue
    |> Enum.reduce(queue_ids, fn item, acc ->
      deps = Map.get(item, :dependencies, []) || []
      Enum.reduce(deps, acc, fn dep, dep_acc -> MapSet.put(dep_acc, dep) end)
    end)
    |> Enum.map(fn id ->
      Map.get(node_map, id) || Map.get(merged_map, id) || %{id: id, title: "Dependency #{id}"}
    end)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.id)
  end

  defp include_dependencies(queue, _graph, _merged_items), do: queue
end
