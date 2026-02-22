defmodule Jido.Lib.Github.Actions.Roadmap.LoadGithubIssues do
  @moduledoc """
  Loads issue candidates from GitHub via gh CLI.
  """

  use Jido.Action,
    name: "roadmap_load_github_issues",
    description: "Load GitHub issues for roadmap",
    compensation: [max_retries: 0],
    schema: [
      repo: [type: :string, required: true],
      repo_slug: [type: {:or, [:string, nil]}, default: nil],
      issue_query: [type: {:or, [:string, nil]}, default: nil],
      github_token: [type: {:or, [:string, nil]}, default: nil]
    ]

  alias Jido.Lib.Github.Actions.Common.CommandRunner
  alias Jido.Lib.Github.Actions.Roadmap.Helpers
  alias Jido.Lib.Github.Helpers, as: GithubHelpers

  @impl true
  def run(params, _context) do
    query = params[:issue_query] || "is:open"
    repo = params[:repo_slug] || params.repo

    env_export =
      case params[:github_token] do
        token when is_binary(token) and token != "" ->
          "export GH_TOKEN=#{GithubHelpers.shell_escape(token)} && "

        _ ->
          ""
      end

    cmd =
      env_export <>
        "gh issue list --repo #{GithubHelpers.shell_escape(repo)} --search #{GithubHelpers.shell_escape(query)} --limit 200 --json number,title,state,labels,url"

    github_items =
      case CommandRunner.run_local(cmd, repo_dir: ".", params: %{apply: true, mode: :safe_fix}) do
        {:ok, %{output: output}} -> decode_issues(output)
        _ -> []
      end

    {:ok, Helpers.pass_through(params) |> Map.put(:github_items, github_items)}
  end

  defp decode_issues(output) when is_binary(output) do
    case Jason.decode(output) do
      {:ok, items} when is_list(items) ->
        Enum.map(items, fn item ->
          %{
            id: "GH-#{item["number"]}",
            title: item["title"] || "",
            source: :github,
            issue_number: item["number"],
            issue_url: item["url"],
            labels: Enum.map(item["labels"] || [], &(&1["name"] || ""))
          }
        end)

      _ ->
        []
    end
  end

  defp decode_issues(_), do: []
end
