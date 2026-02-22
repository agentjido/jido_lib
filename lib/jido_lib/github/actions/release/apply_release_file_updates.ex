defmodule Jido.Lib.Github.Actions.Release.ApplyReleaseFileUpdates do
  @moduledoc """
  Applies release file updates (version/changelog) when mutation is enabled.
  """

  use Jido.Action,
    name: "release_apply_file_updates",
    description: "Apply release version/changelog updates",
    compensation: [max_retries: 0],
    schema: [
      repo_dir: [type: :string, required: true],
      next_version: [type: :string, required: true],
      changelog: [type: :string, required: true],
      apply: [type: :boolean, default: false],
      publish: [type: :boolean, default: false],
      dry_run: [type: :boolean, default: true]
    ]

  alias Jido.Lib.Github.Actions.Common.MutationGuard
  alias Jido.Lib.Github.Actions.Release.Helpers

  @impl true
  def run(params, _context) do
    if MutationGuard.mutation_allowed?(params) do
      with :ok <- update_mix_version(params.repo_dir, params.next_version),
           :ok <- update_changelog(params.repo_dir, params.changelog) do
        {:ok,
         Helpers.pass_through(params)
         |> Map.put(:release_plan, %{updated: true, version: params.next_version})}
      else
        {:error, reason} -> {:error, {:release_apply_file_updates_failed, reason}}
      end
    else
      {:ok,
       Helpers.pass_through(params)
       |> Map.put(:release_plan, %{updated: false, version: params.next_version, dry_run: true})}
    end
  end

  defp update_mix_version(repo_dir, version) do
    mix_file = Path.join(repo_dir, "mix.exs")

    with {:ok, content} <- File.read(mix_file),
         next <- String.replace(content, ~r/@version\s+"[^"]+"/, "@version \"#{version}\""),
         :ok <- File.write(mix_file, next) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_changelog(repo_dir, changelog_entry) do
    changelog_file = Path.join(repo_dir, "CHANGELOG.md")

    case File.read(changelog_file) do
      {:ok, content} ->
        File.write(changelog_file, changelog_entry <> "\n\n" <> content)

      {:error, :enoent} ->
        File.write(changelog_file, "# Changelog\n\n" <> changelog_entry <> "\n")

      {:error, reason} ->
        {:error, reason}
    end
  end
end
