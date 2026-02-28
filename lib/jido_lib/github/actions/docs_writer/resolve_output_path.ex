defmodule Jido.Lib.Github.Actions.DocsWriter.ResolveOutputPath do
  @moduledoc """
  Resolves the output file path from content metadata or explicit override.

  If no explicit `output_path` is given, derives it from `destination_route`
  and `destination_collection` in the content metadata, producing a `.livemd`
  path under `priv/<collection>/`.
  """

  use Jido.Action,
    name: "docs_writer_resolve_output_path",
    description: "Resolve output path from content metadata or explicit value",
    compensation: [max_retries: 0],
    schema: [
      content_metadata: [type: :map, default: %{}],
      output_path: [type: {:or, [:string, nil]}, default: nil]
    ]

  alias Jido.Lib.Github.Actions.DocsWriter.Helpers

  @impl true
  def run(params, _context) do
    path =
      if is_binary(params[:output_path]) and String.trim(params.output_path) != "" do
        params.output_path
      else
        derive_from_metadata(params[:content_metadata] || %{})
      end

    {:ok,
     params
     |> Helpers.pass_through()
     |> Map.put(:output_path, path)}
  end

  defp derive_from_metadata(metadata) do
    route = Map.get(metadata, :destination_route)

    if is_binary(route) and String.trim(route) != "" do
      route = String.trim_leading(route, "/")
      collection = Map.get(metadata, :destination_collection, :pages)
      "priv/#{collection}/#{route}.livemd"
    else
      nil
    end
  end
end
