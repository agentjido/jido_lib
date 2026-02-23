defmodule Jido.Lib.Github.Actions.RunSetupCommands do
  @moduledoc """
  Run repository setup commands.
  """

  use Jido.Action,
    name: "run_setup_commands",
    description: "Run setup command batch in repo",
    compensation: [max_retries: 0],
    schema: [
      provider: [type: :atom, default: :claude],
      single_pass: [type: :boolean, default: false],
      repo_dir: [type: :string, required: true],
      session_id: [type: :string, required: true],
      commands: [type: {:list, :string}, default: []],
      setup_commands: [type: {:list, :string}, default: []],
      timeout: [type: :integer, default: 300_000],
      fail_mode: [type: :atom, default: :halt_on_first],
      return_results: [type: :boolean, default: false],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent]
    ]

  alias Jido.Lib.Github.Actions.RunRepoCommands

  @impl true
  def run(params, context) do
    params
    |> Map.put(:phase, :setup)
    |> RunRepoCommands.run(context)
  end
end
