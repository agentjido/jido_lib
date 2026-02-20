defmodule Jido.Lib.Github.Actions.PrBot.CommentIssueWithPr do
  @moduledoc """
  Post the created PR URL back to the source issue.
  """

  use Jido.Action,
    name: "comment_issue_with_pr",
    description: "Comment source issue with created PR link",
    schema: [
      owner: [type: :string, required: true],
      repo: [type: :string, required: true],
      provider: [type: :atom, default: :claude],
      issue_number: [type: :integer, required: true],
      run_id: [type: :string, required: true],
      session_id: [type: :string, required: true],
      repo_dir: [type: :string, required: true],
      branch_name: [type: :string, required: true],
      commit_sha: [type: {:or, [:string, nil]}, default: nil],
      pr_url: [type: :string, required: true],
      timeout: [type: :integer, default: 300_000],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent]
    ]

  require Logger

  alias Jido.Lib.Github.Actions.PrBot.Helpers

  @impl true
  def run(params, _context) do
    agent_mod = params[:shell_agent_mod] || Jido.Shell.Agent
    timeout = params[:timeout] || 300_000
    comment_body = build_comment_body(params)
    body_file = "/tmp/jido_pr_issue_comment_#{params.run_id}.md"
    escaped_body_file = Helpers.escape_path(body_file)

    write_cmd =
      "cat > #{escaped_body_file} << 'JIDO_ISSUE_PR_EOF'\n#{comment_body}\nJIDO_ISSUE_PR_EOF"

    with {:ok, _} <-
           Helpers.run_in_dir(agent_mod, params.session_id, params.repo_dir, write_cmd,
             timeout: 10_000
           ) do
      cmd =
        "gh issue comment #{params.issue_number} --repo #{params.owner}/#{params.repo} --body-file #{escaped_body_file}"

      Logger.info(
        "[PrBot] Commenting issue #{params.owner}/#{params.repo}##{params.issue_number} with PR URL"
      )

      case Helpers.run_in_dir(agent_mod, params.session_id, params.repo_dir, cmd,
             timeout: timeout
           ) do
        {:ok, _} ->
          {:ok,
           Map.merge(Helpers.pass_through(params), %{
             issue_comment_posted: true,
             issue_comment_error: nil
           })}

        {:error, reason} ->
          {:ok,
           Map.merge(Helpers.pass_through(params), %{
             issue_comment_posted: false,
             issue_comment_error: inspect(reason)
           })}
      end
    else
      {:error, reason} ->
        {:ok,
         Map.merge(Helpers.pass_through(params), %{
           issue_comment_posted: false,
           issue_comment_error: inspect({:comment_body_write_failed, reason})
         })}
    end
  end

  defp build_comment_body(params) do
    """
    ✅ Automated PR created for this issue.

    - PR: #{params.pr_url}
    - Branch: `#{params.branch_name}`
    - Commit: `#{params[:commit_sha] || "unknown"}`
    - Run ID: `#{params.run_id}`
    """
    |> String.trim()
  end
end
