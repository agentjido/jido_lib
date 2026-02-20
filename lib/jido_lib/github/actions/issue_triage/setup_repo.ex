defmodule Jido.Lib.Github.Actions.IssueTriage.SetupRepo do
  @moduledoc """
  Run setup commands in the cloned repository.
  """

  use Jido.Action,
    name: "setup_repo",
    description: "Run setup commands in the cloned repository",
    schema: [
      provider: [type: :atom, default: :claude],
      repo_dir: [type: :string, required: true],
      session_id: [type: :string, required: true],
      setup_commands: [type: {:list, :string}, default: []],
      timeout: [type: :integer, default: 300_000],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent]
    ]

  alias Jido.Lib.Github.Actions.IssueTriage.Helpers

  @impl true
  def run(params, _context) do
    commands = params[:setup_commands] || []
    agent_mod = params[:shell_agent_mod] || Jido.Shell.Agent

    Enum.reduce_while(commands, :ok, fn cmd, :ok ->
      case Helpers.run_in_dir(agent_mod, params.session_id, params.repo_dir, cmd,
             timeout: params[:timeout] || 180_000
           ) do
        {:ok, _stdout} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:setup_failed, cmd, reason}}}
      end
    end)
    |> case do
      :ok -> {:ok, Helpers.pass_through(params)}
      {:error, _} = error -> error
    end
  end
end
