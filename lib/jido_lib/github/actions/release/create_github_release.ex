defmodule Jido.Lib.Github.Actions.Release.CreateGithubRelease do
  @moduledoc """
  Creates GitHub release entry for tag when publish mode is enabled.
  """

  use Jido.Action,
    name: "release_create_github_release",
    description: "Create GitHub release",
    compensation: [max_retries: 0],
    schema: [
      repo: [type: :string, required: true],
      repo_dir: [type: :string, required: true],
      next_version: [type: :string, required: true],
      changelog: [type: :string, required: true],
      publish: [type: :boolean, default: false],
      apply: [type: :boolean, default: false],
      github_token: [type: {:or, [:string, nil]}, default: nil]
    ]

  alias Jido.Lib.Github.Actions.Common.CommandRunner
  alias Jido.Lib.Github.Actions.Common.MutationGuard
  alias Jido.Lib.Github.Actions.Release.Helpers

  @impl true
  def run(params, _context) do
    if MutationGuard.mutation_allowed?(params, publish_only: true) do
      notes_file = Path.join(System.tmp_dir!(), "jido-release-notes-#{params.next_version}.md")
      :ok = File.write!(notes_file, params.changelog)

      env_export =
        case params[:github_token] do
          token when is_binary(token) and token != "" -> "export GH_TOKEN=#{token} && "
          _ -> ""
        end

      cmd =
        env_export <>
          "gh release create v#{params.next_version} --repo #{params.repo} --title v#{params.next_version} --notes-file #{notes_file}"

      case CommandRunner.run_local(cmd, repo_dir: params.repo_dir, params: params) do
        {:ok, _} -> {:ok, Helpers.pass_through(params)}
        {:error, reason} -> {:error, {:release_create_github_release_failed, reason}}
      end
    else
      {:ok, Helpers.pass_through(params)}
    end
  end
end
