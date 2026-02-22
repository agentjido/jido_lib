defmodule Jido.Lib.Github.Actions.Release.PushBranchAndTag do
  @moduledoc """
  Pushes branch and tags to origin when publish mode is enabled.
  """

  use Jido.Action,
    name: "release_push_branch_and_tag",
    description: "Push release branch and tag",
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

  @impl true
  def run(params, _context) do
    if MutationGuard.mutation_allowed?(params, publish_only: true) do
      with {:ok, _} <-
             CommandRunner.run_local("git push origin HEAD",
               repo_dir: params.repo_dir,
               params: params
             ),
           {:ok, _} <-
             CommandRunner.run_local(
               "git push origin v#{params.next_version}",
               repo_dir: params.repo_dir,
               params: params
             ) do
        {:ok, Helpers.pass_through(params)}
      else
        {:error, reason} -> {:error, {:release_push_branch_and_tag_failed, reason}}
      end
    else
      {:ok, Helpers.pass_through(params)}
    end
  end
end
