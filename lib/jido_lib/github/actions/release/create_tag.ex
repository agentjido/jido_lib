defmodule Jido.Lib.Github.Actions.Release.CreateTag do
  @moduledoc """
  Creates release git tag when publish mode is enabled.
  """

  use Jido.Action,
    name: "release_create_tag",
    description: "Create release tag",
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
      case CommandRunner.run_local("git tag v#{params.next_version}",
             repo_dir: params.repo_dir,
             params: params
           ) do
        {:ok, _} -> {:ok, Helpers.pass_through(params)}
        {:error, reason} -> {:error, {:release_create_tag_failed, reason}}
      end
    else
      {:ok, Helpers.pass_through(params)}
    end
  end
end
