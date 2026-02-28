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

  defp has_drift?(repos, source_files, last_sha) do
    Enum.any?(repos, fn repo_spec ->
      {owner, repo} = parse_repo_spec(repo_spec)

      Enum.any?(source_files, fn file ->
        case System.cmd("gh", ["api", "repos/#{owner}/#{repo}/compare/#{last_sha}...HEAD",
               "--jq", ".files[].filename"], stderr_to_stdout: true) do
          {output, 0} ->
            changed_files = String.split(String.trim(output), "\n", trim: true)
            file in changed_files

          _ ->
            # API call failed (bad SHA, rate limit, etc.) — flag as potentially drifted
            Mix.shell().info("    (could not verify #{owner}/#{repo} @ #{last_sha})")
            true
        end
      end)
    end)
  end

  defp parse_repo_spec(spec) when is_binary(spec) do
    # Handles "owner/repo:alias" and "owner/repo" formats
    slug =
      case String.split(spec, ":", parts: 2) do
        [slug, _alias] -> slug
        [slug] -> slug
      end

    case String.split(slug, "/", parts: 2) do
      [owner, repo] -> {owner, repo}
      _ -> {"unknown", spec}
    end
  end
end
