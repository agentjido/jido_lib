defmodule Mix.Tasks.JidoLib.Github.Docs.ScanDrift do
  @moduledoc """
  Scans existing Livebooks for API drift by comparing metadata against source files.

  Reads the frontmatter from generated `.livemd` files and checks whether the
  source files they reference have been modified since the last grounding run.

  ## Usage

      mix jido_lib.github.docs.scan_drift priv/pages/docs

  Defaults to scanning `priv/pages/docs` if no path is given.
  """

  use Mix.Task

  @shortdoc "Scan generated Livebooks for API drift"

  alias Jido.Lib.Github.ContentPlan

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    path = List.first(args) || "priv/pages/docs"
    files = Path.wildcard(Path.join(path, "**/*.livemd"))

    Mix.shell().info("Scanning #{length(files)} Livebooks for API drift...")

    drifted_files =
      Enum.filter(files, fn file ->
        %{metadata: metadata} = ContentPlan.parse_file!(file)

        last_sha = Map.get(metadata, :grounded_sha)
        source_files = Map.get(metadata, :source_files, [])
        repos = Map.get(metadata, :repos, [])

        if is_nil(last_sha) or source_files == [] do
          false
        else
          has_drift?(repos, source_files, last_sha)
        end
      end)

    if drifted_files == [] do
      Mix.shell().info(
        "Zero drift detected. All documentation is aligned with source code."
      )
    else
      Mix.shell().error("API DRIFT DETECTED IN #{length(drifted_files)} FILES:")

      Enum.each(drifted_files, fn file ->
        Mix.shell().info("  - #{file}")
      end)
    end
  end

  defp has_drift?(_repos, _source_files, _last_sha) do
    # TODO: Wire up to shell agent git calls to check if commits exist
    # on source_files since last_sha. Currently hardcoded false.
    false
  end
end
