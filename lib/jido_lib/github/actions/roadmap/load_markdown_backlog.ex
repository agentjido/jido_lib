defmodule Jido.Lib.Github.Actions.Roadmap.LoadMarkdownBacklog do
  @moduledoc """
  Loads roadmap items from markdown backlog files.
  """

  use Jido.Action,
    name: "roadmap_load_markdown_backlog",
    description: "Load markdown backlog",
    compensation: [max_retries: 0],
    schema: [
      repo_dir: [type: :string, required: true],
      stories_dirs: [type: {:list, :string}, default: ["specs/stories"]]
    ]

  alias Jido.Lib.Github.Actions.Roadmap.Helpers

  @story_heading ~r/^###\s+(ST-[A-Z]+-[0-9]{3})\s*(.*)$/m

  @impl true
  def run(params, _context) do
    markdown_items =
      params[:stories_dirs]
      |> Enum.flat_map(&collect_markdown_files(params.repo_dir, &1))
      |> Enum.flat_map(&extract_items/1)

    {:ok, Helpers.pass_through(params) |> Map.put(:markdown_items, markdown_items)}
  end

  defp collect_markdown_files(repo_dir, dir) when is_binary(repo_dir) and is_binary(dir) do
    path = Path.join(repo_dir, dir)

    if File.dir?(path) do
      path
      |> Path.join("**/*.md")
      |> Path.wildcard()
    else
      []
    end
  end

  defp extract_items(file) do
    case File.read(file) do
      {:ok, content} ->
        Regex.scan(@story_heading, content)
        |> Enum.map(fn [_all, story_id, title] ->
          %{
            id: story_id,
            title: String.trim(title),
            source: :markdown,
            file: file,
            dependencies: extract_dependencies(content, story_id)
          }
        end)

      _ ->
        []
    end
  end

  defp extract_dependencies(content, story_id) do
    dependency_regex =
      ~r/###\s+#{Regex.escape(story_id)}.*?####\s+Dependencies\s*(.*?)\n####/ms

    case Regex.run(dependency_regex, content) do
      [_, block] ->
        Regex.scan(~r/ST-[A-Z]+-[0-9]{3}/, block)
        |> List.flatten()
        |> Enum.uniq()

      _ ->
        []
    end
  end
end
