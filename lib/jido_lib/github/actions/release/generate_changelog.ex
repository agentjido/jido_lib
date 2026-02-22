defmodule Jido.Lib.Github.Actions.Release.GenerateChangelog do
  @moduledoc """
  Generates release changelog content.
  """

  use Jido.Action,
    name: "release_generate_changelog",
    description: "Generate changelog draft",
    compensation: [max_retries: 0],
    schema: [
      repo_dir: [type: :string, required: true],
      next_version: [type: :string, required: true]
    ]

  alias Jido.Lib.Github.Actions.Release.Helpers

  @impl true
  def run(params, _context) do
    log_entries = git_log(params.repo_dir)
    date = Date.utc_today() |> Date.to_iso8601()

    changelog =
      "## v#{params.next_version} (#{date})\n\n" <>
        if log_entries == [],
          do: "- Maintenance release",
          else: Enum.map_join(log_entries, "\n", &"- #{&1}")

    {:ok, Helpers.pass_through(params) |> Map.put(:changelog, changelog)}
  end

  defp git_log(repo_dir) do
    cmd =
      "cd #{Jido.Lib.Github.Helpers.escape_path(repo_dir)} && git log --pretty=format:'%s' -n 20"

    case System.cmd("bash", ["-lc", cmd], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.reject(&(&1 == ""))

      _ ->
        []
    end
  rescue
    _ ->
      []
  end
end
