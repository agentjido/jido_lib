defmodule Jido.Lib.Github.Actions.Roadmap.CommitPerItem do
  @moduledoc """
  Creates one commit per successful roadmap item.
  """

  use Jido.Action,
    name: "roadmap_commit_per_item",
    description: "Commit roadmap items one-by-one",
    compensation: [max_retries: 0],
    schema: [
      repo_dir: [type: :string, required: true],
      queue_results: [type: {:list, :map}, default: []],
      apply: [type: :boolean, default: false]
    ]

  alias Jido.Lib.Github.Actions.Common.CommandRunner
  alias Jido.Lib.Github.Actions.Common.MutationGuard
  alias Jido.Lib.Github.Actions.Roadmap.Helpers
  alias Jido.Lib.Github.Helpers, as: GithubHelpers

  @impl true
  def run(params, _context) do
    if params[:apply] == true and MutationGuard.mutation_allowed?(params) do
      commit_items(params)
    else
      {:ok,
       Helpers.pass_through(params)
       |> Map.put(:committed_items, [])
       |> Map.put(:warnings, ["commit skipped: dry-run mode"])}
    end
  end

  defp commit_items(params) do
    items_to_commit =
      params.queue_results
      |> Enum.filter(&(&1[:status] == :completed))

    Enum.reduce_while(items_to_commit, {:ok, []}, fn item, {:ok, acc} ->
      case commit_item(item, params) do
        {:ok, commit_info} ->
          {:cont, {:ok, [commit_info | acc]}}

        {:error, reason} ->
          {:halt, {:error, {:roadmap_commit_per_item_failed, reason, Enum.reverse(acc)}}}
      end
    end)
    |> case do
      {:ok, commits} ->
        {:ok, Helpers.pass_through(params) |> Map.put(:committed_items, Enum.reverse(commits))}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp commit_item(item, params) do
    commit_message =
      "feat(roadmap): #{item[:id]} #{item[:title]}"
      |> String.trim()
      |> String.slice(0, 120)

    with {:ok, _} <-
           CommandRunner.run_local("git add -A", repo_dir: params.repo_dir, params: params),
         {:ok, has_changes} <- has_staged_changes?(params.repo_dir),
         {:ok, _} <- maybe_commit(has_changes, commit_message, params) do
      {:ok, %{id: item[:id], status: :committed, message: commit_message, changed: has_changes}}
    else
      {:skip, :no_changes} ->
        {:ok, %{id: item[:id], status: :skipped, reason: :no_changes}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp has_staged_changes?(repo_dir) do
    cmd = "cd #{GithubHelpers.escape_path(repo_dir)} && git diff --cached --name-only"

    case System.cmd("bash", ["-lc", cmd], stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output) != ""}
      {_output, _code} -> {:error, :git_diff_failed}
    end
  rescue
    _ -> {:error, :git_diff_failed}
  end

  defp maybe_commit(false, _message, _params), do: {:skip, :no_changes}

  defp maybe_commit(true, message, params) do
    CommandRunner.run_local(
      "git commit -m #{GithubHelpers.shell_escape(message)}",
      repo_dir: params.repo_dir,
      params: params
    )
  end
end
