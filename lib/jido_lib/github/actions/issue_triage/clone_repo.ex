defmodule Jido.Lib.Github.Actions.IssueTriage.CloneRepo do
  @moduledoc """
  Clone the target repository into the Sprite workspace.
  """

  use Jido.Action,
    name: "clone_repo",
    description: "Clone the repository into the sprite workspace",
    schema: [
      owner: [type: :string, required: true],
      repo: [type: :string, required: true],
      workspace_dir: [type: :string, required: true],
      session_id: [type: :string, required: true],
      timeout: [type: :integer, default: 300_000],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent]
    ]

  alias Jido.Lib.Github.Actions.IssueTriage.Helpers

  @impl true
  def run(params, _context) do
    url = "https://github.com/#{params.owner}/#{params.repo}.git"
    repo_dir = Path.join(params.workspace_dir, params.repo)
    cmd = "git clone --depth 1 #{url} #{repo_dir}"

    agent_mod = params[:shell_agent_mod] || Jido.Shell.Agent

    case Helpers.run(agent_mod, params.session_id, cmd, timeout: params[:timeout] || 120_000) do
      {:ok, _stdout} ->
        {:ok, Map.merge(Helpers.pass_through(params), %{repo_dir: repo_dir})}

      {:error, reason} ->
        {:error, {:clone_failed, reason}}
    end
  end
end
