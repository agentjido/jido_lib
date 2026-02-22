defmodule Jido.Lib.Github.Actions.Release.CommitReleaseArtifacts do
  @moduledoc """
  Commits release artifacts when publish mode is enabled.
  """

  use Jido.Action,
    name: "release_commit_artifacts",
    description: "Commit release artifacts",
    compensation: [max_retries: 0],
    schema: [
      repo_dir: [type: :string, required: true],
      next_version: [type: :string, required: true],
      publish: [type: :boolean, default: false],
      apply: [type: :boolean, default: false]
    ]

  alias Jido.Lib.Github.Actions.Common.CommandRunner
  alias Jido.Lib.Github.Actions.Common.MutationGuard
  alias Jido.Lib.Github.Actions.Release.Helpers
  alias Jido.Lib.Github.Helpers, as: GithubHelpers

  @impl true
  def run(params, _context) do
    if MutationGuard.mutation_allowed?(params, publish_only: true) do
      with {:ok, _} <-
             CommandRunner.run_local("git add -A", repo_dir: params.repo_dir, params: params),
           {:ok, _} <-
             CommandRunner.run_local(
               "git commit -m #{GithubHelpers.shell_escape("chore(release): v#{params.next_version}")}",
               repo_dir: params.repo_dir,
               params: params
             ) do
        {:ok, Helpers.pass_through(params)}
      else
        {:error, reason} -> {:error, {:release_commit_artifacts_failed, reason}}
      end
    else
      {:ok, Helpers.pass_through(params) |> Map.put(:warnings, ["commit skipped: dry-run mode"])}
    end
  end
end
