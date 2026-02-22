defmodule Jido.Lib.Github.Actions.Roadmap.MergeRoadmapSources do
  @moduledoc """
  Merges markdown and GitHub issue roadmap sources.
  """

  use Jido.Action,
    name: "roadmap_merge_sources",
    description: "Merge roadmap item sources",
    compensation: [max_retries: 0],
    schema: [
      markdown_items: [type: {:list, :map}, default: []],
      github_items: [type: {:list, :map}, default: []]
    ]

  alias Jido.Lib.Github.Actions.Roadmap.Helpers

  @impl true
  def run(params, _context) do
    merged_items =
      (params[:markdown_items] ++ params[:github_items])
      |> Enum.uniq_by(& &1.id)

    {:ok, Helpers.pass_through(params) |> Map.put(:merged_items, merged_items)}
  end
end
