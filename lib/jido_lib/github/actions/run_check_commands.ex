defmodule Jido.Lib.Github.Actions.RunCheckCommands do
  @moduledoc """
  Run repository check commands.
  """

  use Jido.Action,
    name: "run_check_commands",
    description: "Run check command batch in repo",
    compensation: [max_retries: 0],
    schema: [
      provider: [type: :atom, default: :claude],
      repo_dir: [type: :string, required: true],
      session_id: [type: :string, required: true],
      commands: [type: {:list, :string}, default: []],
      check_commands: [type: {:list, :string}, default: []],
      timeout: [type: :integer, default: 300_000],
      fail_mode: [type: :atom, default: :halt_on_first],
      return_results: [type: :boolean, default: false],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent]
    ]

  alias Jido.Lib.Github.Actions.RunRepoCommands

  @impl true
  def run(params, context) do
    params
    |> Map.put(:phase, :checks)
    |> RunRepoCommands.run(context)
  end
end
