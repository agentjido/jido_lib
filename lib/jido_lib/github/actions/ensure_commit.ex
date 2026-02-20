defmodule Jido.Lib.Github.Actions.EnsureCommit do
  @moduledoc """
  Ensure there is at least one commit on the working branch and produce commit metadata.
  """

  use Jido.Action,
    name: "ensure_commit",
    description: "Validate or create commit for PR branch",
    compensation: [max_retries: 0],
    schema: [
      repo: [type: :string, required: true],
      provider: [type: :atom, default: :claude],
      issue_number: [type: :integer, required: true],
      repo_dir: [type: :string, required: true],
      session_id: [type: :string, required: true],
      base_sha: [type: :string, required: true],
      timeout: [type: :integer, default: 300_000],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent]
    ]

  alias Jido.Lib.Github.Helpers

  @impl true
  def run(params, _context) do
    agent_mod = params[:shell_agent_mod] || Jido.Shell.Agent
    timeout = params[:timeout] || 300_000

    with {:ok, commit_count} <- commit_count(params, agent_mod, timeout),
         {:ok, dirty?} <- dirty_tree?(params, agent_mod, timeout),
         {:ok, fallback_used?} <-
           maybe_fallback_commit(params, agent_mod, timeout, commit_count, dirty?),
         {:ok, final_count} <- commit_count(params, agent_mod, timeout),
         true <- final_count > 0 or {:error, :no_changes},
         {:ok, commit_sha} <- head_sha(params, agent_mod, timeout) do
      {:ok,
       Map.merge(Helpers.pass_through(params), %{
         commit_sha: commit_sha,
         commits_since_base: final_count,
         fallback_commit_used: fallback_used?
       })}
    else
      {:error, reason} ->
        {:error, {:ensure_commit_failed, reason}}

      false ->
        {:error, {:ensure_commit_failed, :no_changes}}
    end
  end

  defp maybe_fallback_commit(_params, _agent_mod, _timeout, 0, false), do: {:error, :no_changes}
  defp maybe_fallback_commit(_params, _agent_mod, _timeout, _count, false), do: {:ok, false}

  defp maybe_fallback_commit(params, agent_mod, timeout, _count, true) do
    cmd =
      "git add -A && git commit -m \"fix(#{params.repo}): address issue ##{params.issue_number}\""

    case Helpers.run_in_dir(agent_mod, params.session_id, params.repo_dir, cmd, timeout: timeout) do
      {:ok, _} -> {:ok, true}
      {:error, reason} -> {:error, {:fallback_commit_failed, reason}}
    end
  end

  defp commit_count(params, agent_mod, timeout) do
    cmd = "git rev-list --count #{params.base_sha}..HEAD"

    with {:ok, output} <-
           Helpers.run_in_dir(agent_mod, params.session_id, params.repo_dir, cmd,
             timeout: timeout
           ),
         {count, ""} <- Integer.parse(String.trim(output)) do
      {:ok, count}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_commit_count}
    end
  end

  defp dirty_tree?(params, agent_mod, timeout) do
    cmd = "git status --porcelain"

    case Helpers.run_in_dir(agent_mod, params.session_id, params.repo_dir, cmd, timeout: timeout) do
      {:ok, output} -> {:ok, String.trim(output) != ""}
      {:error, reason} -> {:error, reason}
    end
  end

  defp head_sha(params, agent_mod, timeout) do
    cmd = "git rev-parse HEAD"

    case Helpers.run_in_dir(agent_mod, params.session_id, params.repo_dir, cmd, timeout: timeout) do
      {:ok, sha} when is_binary(sha) and sha != "" -> {:ok, sha}
      {:ok, _} -> {:error, :missing_head_sha}
      {:error, reason} -> {:error, reason}
    end
  end
end
