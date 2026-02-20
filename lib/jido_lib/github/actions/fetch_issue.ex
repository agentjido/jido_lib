defmodule Jido.Lib.Github.Actions.FetchIssue do
  @moduledoc """
  Fetch issue details from GitHub using `gh issue view` inside the Sprite.
  """

  use Jido.Action,
    name: "fetch_issue",
    description: "Fetch issue details via gh CLI",
    compensation: [max_retries: 1],
    schema: [
      owner: [type: :string, required: true],
      repo: [type: :string, required: true],
      provider: [type: :atom, default: :claude],
      issue_number: [type: :integer, required: true],
      session_id: [type: :string, required: true],
      timeout: [type: :integer, default: 300_000],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent]
    ]

  alias Jido.Lib.Github.Helpers

  @impl true
  def run(params, _context) do
    cmd =
      "gh issue view #{params.issue_number} " <>
        "--repo #{params.owner}/#{params.repo} " <>
        "--json title,body,labels,author,state,url"

    agent_mod = params[:shell_agent_mod] || Jido.Shell.Agent

    with {:ok, stdout} <-
           Helpers.run(agent_mod, params.session_id, cmd, timeout: params[:timeout] || 30_000),
         {:ok, issue} <- Jason.decode(stdout) do
      {:ok,
       Map.merge(Helpers.pass_through(params), %{
         issue_title: issue["title"],
         issue_body: issue["body"] || "",
         issue_labels: Enum.map(issue["labels"] || [], & &1["name"]),
         issue_author: get_in(issue, ["author", "login"]),
         issue_url: issue["url"] || params[:issue_url]
       })}
    else
      {:error, reason} -> {:error, {:fetch_issue_failed, reason}}
    end
  end
end
