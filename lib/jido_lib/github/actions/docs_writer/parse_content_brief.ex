defmodule Jido.Lib.Github.Actions.DocsWriter.ParseContentBrief do
  @moduledoc """
  Parses structured content plan frontmatter from the brief text.

  Extracts `content_metadata`, `prompt_overrides`, and the raw `brief_body`
  from a brief string that uses Elixir map frontmatter format.
  """

  use Jido.Action,
    name: "docs_writer_parse_content_brief",
    description: "Parse content plan frontmatter from brief text",
    compensation: [max_retries: 0],
    schema: [
      brief: [type: :string, required: true]
    ]

  alias Jido.Lib.Github.Actions.DocsWriter.Helpers
  alias Jido.Lib.Github.ContentPlan

  @impl true
  def run(params, _context) do
    %{metadata: parsed_metadata, body: body} = ContentPlan.parse_string!(params.brief)

    # Prefer parsed frontmatter metadata; fall back to intake-provided content_metadata
    # when the brief text has no frontmatter (already separated by the mix task).
    content_metadata =
      if parsed_metadata == %{},
        do: params[:content_metadata] || %{},
        else: parsed_metadata

    prompt_overrides =
      if parsed_metadata == %{},
        do: params[:prompt_overrides] || %{},
        else: Map.get(parsed_metadata, :prompt_overrides, %{})

    {:ok,
     params
     |> Helpers.pass_through()
     |> Map.put(:content_metadata, content_metadata)
     |> Map.put(:prompt_overrides, prompt_overrides)
     |> Map.put(:brief_body, body)}
  end
end
