defmodule Jido.Lib.Github.Actions.PrBot.PushBranch do
  @moduledoc """
  Push the working branch upstream to the origin remote.
  """

  use Jido.Action,
    name: "push_branch",
    description: "Push PR branch to origin",
    schema: [
      owner: [type: :string, required: true],
      repo: [type: :string, required: true],
      provider: [type: :atom, default: :claude],
      repo_dir: [type: :string, required: true],
      session_id: [type: :string, required: true],
      branch_name: [type: :string, required: true],
      timeout: [type: :integer, default: 300_000],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent]
    ]

  alias Jido.Lib.Github.Actions.PrBot.Helpers

  @impl true
  def run(params, _context) do
    agent_mod = params[:shell_agent_mod] || Jido.Shell.Agent
    timeout = params[:timeout] || 300_000

    with {:ok, origin_url} <- origin_url(params, agent_mod, timeout),
         :ok <- ensure_same_repo(origin_url, params.owner, params.repo),
         {:ok, _} <- push_branch(params, agent_mod, timeout) do
      {:ok, Map.merge(Helpers.pass_through(params), %{branch_pushed: true})}
    else
      {:error, reason} ->
        {:error, {:push_branch_failed, reason}}
    end
  end

  defp origin_url(params, agent_mod, timeout) do
    Helpers.run_in_dir(agent_mod, params.session_id, params.repo_dir, "git remote get-url origin",
      timeout: timeout
    )
  end

  defp ensure_same_repo(origin_url, owner, repo) when is_binary(origin_url) do
    expected = "#{owner}/#{repo}"

    if String.contains?(origin_url, expected) do
      :ok
    else
      {:error, {:remote_mismatch, origin_url}}
    end
  end

  defp push_branch(params, agent_mod, timeout) do
    cmd = "git push -u origin #{params.branch_name}"
    Helpers.run_in_dir(agent_mod, params.session_id, params.repo_dir, cmd, timeout: timeout)
  end
end
