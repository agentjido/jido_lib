defmodule Jido.Lib.Github.Actions.PrepareGithubAuth do
  @moduledoc """
  Ensure GitHub auth and git credential plumbing are available inside the Sprite.
  """

  use Jido.Action,
    name: "prepare_github_auth",
    description: "Validate GitHub auth in the sprite session",
    compensation: [max_retries: 1],
    schema: [
      provider: [type: :atom, default: :claude],
      single_pass: [type: :boolean, default: false],
      session_id: [type: :string, required: true],
      timeout: [type: :integer, default: 300_000],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent]
    ]

  alias Jido.Lib.Github.Helpers

  @impl true
  def run(params, _context) do
    agent_mod = params[:shell_agent_mod] || Jido.Shell.Agent
    timeout = params[:timeout] || 30_000

    with :ok <- ensure_token(agent_mod, params.session_id, timeout),
         :ok <- ensure_auth_status(agent_mod, params.session_id, timeout),
         :ok <- setup_git_identity(agent_mod, params.session_id, timeout),
         :ok <- setup_git_auth(agent_mod, params.session_id, timeout) do
      {:ok,
       Map.merge(Helpers.pass_through(params), %{
         github_auth_ready: true,
         github_git_auth_ready: true
       })}
    else
      {:error, reason} ->
        {:error, {:prepare_github_auth_failed, reason}}
    end
  end

  defp ensure_token(agent_mod, session_id, timeout) do
    token_check_cmd =
      "if [ -n \"${GH_TOKEN:-}\" ] || [ -n \"${GITHUB_TOKEN:-}\" ]; then echo present; else echo missing; fi"

    case Helpers.run(agent_mod, session_id, token_check_cmd, timeout: timeout) do
      {:ok, "missing"} -> {:error, :missing_github_token}
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_auth_status(agent_mod, session_id, timeout) do
    auth_status_cmd =
      "gh auth status -h github.com >/dev/null 2>&1 || gh auth status >/dev/null 2>&1"

    case Helpers.run(agent_mod, session_id, auth_status_cmd, timeout: timeout) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:gh_auth_status_failed, reason}}
    end
  end

  defp setup_git_identity(agent_mod, session_id, timeout) do
    commands = [
      "git config --global user.email 'jido-bot@users.noreply.github.com'",
      "git config --global user.name 'Jido Bot'"
    ]

    Enum.reduce_while(commands, :ok, fn cmd, :ok ->
      case Helpers.run(agent_mod, session_id, cmd, timeout: timeout) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:git_identity_failed, cmd, reason}}}
      end
    end)
  end

  defp setup_git_auth(agent_mod, session_id, timeout) do
    case Helpers.run(agent_mod, session_id, "gh auth setup-git", timeout: timeout) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:gh_auth_setup_git_failed, reason}}
    end
  end
end
