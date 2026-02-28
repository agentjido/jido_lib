defmodule Jido.Lib.Github.Actions.DocsWriter.GroundSourceCode do
  @moduledoc """
  Extracts exact source code from repos to ground the writer in truth.

  Reads the `source_files` declared in `content_metadata` from the cloned
  repositories inside the sprite, producing a `grounded_context` string that
  contains the verbatim source code. This eliminates hallucination by giving
  the writer the exact API signatures and implementations.
  """

  use Jido.Action,
    name: "docs_writer_ground_source_code",
    description: "Extract source code from repos for semantic grounding",
    compensation: [max_retries: 0],
    schema: [
      content_metadata: [type: :map, default: %{}],
      repo_contexts: [type: {:list, :map}, default: []],
      session_id: [type: :string, required: true],
      workspace_dir: [type: {:or, [:string, nil]}, default: nil],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent]
    ]

  alias Jido.Lib.Github.Actions.DocsWriter.Helpers
  alias Jido.Lib.Github.Helpers, as: GithubHelpers

  # Keep under ~250 lines per file to avoid 414 URI Too Long from the Sprites
  # API when the combined grounded_context is embedded in the docs brief.
  @max_lines 250

  @impl true
  def run(params, _context) do
    files = Map.get(params[:content_metadata] || %{}, :source_files, [])
    agent_mod = params[:shell_agent_mod] || Jido.Shell.Agent

    excerpts =
      Enum.reduce(files, %{}, fn file_path, acc ->
        content = read_source_file(params, agent_mod, file_path)
        Map.put(acc, file_path, content)
      end)

    grounded_context =
      Enum.map_join(excerpts, "\n\n", fn {path, code} ->
        "### Source File: `#{path}`\n```elixir\n#{code}\n```"
      end)

    {:ok,
     params
     |> Helpers.pass_through()
     |> Map.put(:grounded_sources, excerpts)
     |> Map.put(:grounded_context, grounded_context)}
  end

  defp read_source_file(params, agent_mod, file_path) do
    Enum.find_value(params.repo_contexts, "*(CRITICAL WARNING: File not found)*", fn repo_ctx ->
      dir =
        Map.get(repo_ctx, :repo_dir) ||
          Path.join(params[:workspace_dir] || "/work", Map.get(repo_ctx, :rel_dir, ""))

      escaped = GithubHelpers.shell_escape_path(file_path)
      # Use test -f to gate the cat so a missing file yields a non-zero exit code
      # instead of piping cat's stderr through head (which exits 0 and leaks the
      # error message as "valid" content).
      cmd = "test -f #{escaped} && cat #{escaped} | head -n #{@max_lines}"

      case GithubHelpers.run_in_dir(agent_mod, params.session_id, dir, cmd, timeout: 10_000) do
        {:ok, text} when is_binary(text) and text != "" ->
          # Extra safety: reject leaked shell error messages
          trimmed = String.trim(text)

          if String.starts_with?(trimmed, "cat:") or
               String.contains?(trimmed, "No such file or directory") do
            nil
          else
            text
          end

        _ ->
          nil
      end
    end)
  end
end
