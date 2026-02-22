defmodule Jido.Lib.Github.Actions.Roadmap.PushOrOpenPr do
  @moduledoc """
  Optionally pushes roadmap commits and opens a PR.
  """

  use Jido.Action,
    name: "roadmap_push_or_open_pr",
    description: "Push roadmap changes and optionally open PR",
    compensation: [max_retries: 0],
    schema: [
      repo: [type: :string, required: true],
      repo_slug: [type: {:or, [:string, nil]}, default: nil],
      repo_dir: [type: :string, required: true],
      push: [type: :boolean, default: false],
      open_pr: [type: :boolean, default: false],
      apply: [type: :boolean, default: false],
      github_token: [type: {:or, [:string, nil]}, default: nil]
    ]

  alias Jido.Lib.Github.Actions.Common.CommandRunner
  alias Jido.Lib.Github.Actions.Common.MutationGuard
  alias Jido.Lib.Github.Actions.Roadmap.Helpers
  alias Jido.Lib.Github.Helpers, as: GithubHelpers

  @impl true
  def run(params, _context) do
    with :ok <- maybe_push(params),
         {:ok, pr_result} <- maybe_open_pr(params) do
      {:ok,
       Helpers.pass_through(params)
       |> Map.put(:push_result, push_result(params))
       |> Map.put(:pr_result, pr_result)}
    else
      {:error, reason} ->
        {:error, {:roadmap_push_or_open_pr_failed, reason}}
    end
  end

  defp maybe_push(params) do
    cond do
      params[:push] != true ->
        :ok

      MutationGuard.mutation_allowed?(params) ->
        case CommandRunner.run_local("git push origin HEAD",
               repo_dir: params.repo_dir,
               params: params
             ) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, {:push_failed, reason}}
        end

      true ->
        {:error, :mutation_not_allowed}
    end
  end

  defp maybe_open_pr(params) do
    cond do
      params[:open_pr] != true ->
        {:ok, :skipped}

      params[:push] != true ->
        {:error, :open_pr_requires_push}

      MutationGuard.mutation_allowed?(params) ->
        repo = params[:repo_slug] || params.repo
        env_prefix = maybe_env_prefix(params[:github_token])

        cmd =
          env_prefix <>
            "gh pr create --repo #{GithubHelpers.shell_escape(repo)} --fill --base main --head HEAD"

        case CommandRunner.run_local(cmd, repo_dir: params.repo_dir, params: params) do
          {:ok, result} -> {:ok, %{status: :opened, output: result.output}}
          {:error, reason} -> {:error, {:open_pr_failed, reason}}
        end

      true ->
        {:error, :mutation_not_allowed}
    end
  end

  defp maybe_env_prefix(token) when is_binary(token) and token != "" do
    "export GH_TOKEN=#{GithubHelpers.shell_escape(token)} && "
  end

  defp maybe_env_prefix(_token), do: ""

  defp push_result(params) do
    cond do
      params[:push] != true -> :skipped
      params[:apply] != true -> :skipped_dry_run
      true -> :pushed
    end
  end
end
