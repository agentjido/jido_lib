defmodule Jido.Lib.Github.ContentPlan do
  @moduledoc """
  Parses Elixir map frontmatter from content plan markdown files.

  Content plan files use an Elixir map literal as frontmatter, separated from
  the body by a `---` delimiter on its own line. Example:

      %{
        status: :published,
        title: "My Guide",
        destination_route: "/docs/learn/my-guide"
      }
      ---
      The body of the content plan goes here.
  """

  @type parsed :: %{metadata: map(), body: String.t()}

  @doc "Parse a content plan file from disk."
  @spec parse_file!(Path.t()) :: parsed()
  def parse_file!(path) when is_binary(path) do
    content = File.read!(path)
    parse_string!(content)
  end

  @doc "Parse a content plan from a string."
  @spec parse_string!(String.t()) :: parsed()
  def parse_string!(content) when is_binary(content) do
    case String.split(content, ~r/\r?\n---\r?\n/, parts: 2) do
      [frontmatter_str, body] ->
        if String.starts_with?(String.trim(frontmatter_str), "%{") do
          try do
            {metadata, _binding} = Code.eval_string(frontmatter_str)

            if is_map(metadata) do
              %{metadata: metadata, body: String.trim(body)}
            else
              %{metadata: %{}, body: String.trim(content)}
            end
          rescue
            _ -> %{metadata: %{}, body: String.trim(content)}
          end
        else
          %{metadata: %{}, body: String.trim(content)}
        end

      _ ->
        %{metadata: %{}, body: String.trim(content)}
    end
  end
end
