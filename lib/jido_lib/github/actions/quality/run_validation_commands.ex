defmodule Jido.Lib.Github.Actions.Quality.RunValidationCommands do
  @moduledoc """
  Runs final validation commands after optional safe fixes.
  """

  use Jido.Action,
    name: "quality_run_validation_commands",
    description: "Run quality validation commands",
    compensation: [max_retries: 0],
    schema: [
      repo_dir: [type: :string, required: true],
      policy: [type: :map, required: true],
      mode: [type: :atom, default: :report],
      apply: [type: :boolean, default: false]
    ]

  alias Jido.Lib.Github.Actions.Common.CommandRunner
  alias Jido.Lib.Github.Actions.Quality.Helpers

  @impl true
  def run(params, _context) do
    commands = Map.get(params.policy, :validation_commands, ["mix quality"])

    case CommandRunner.run_check_commands(commands, params.repo_dir, params) do
      {:ok, results} ->
        {:ok,
         Helpers.pass_through(params)
         |> Map.put(:validation_results, results)
         |> Map.put(:status, :completed)}

      {:error, results} ->
        {:error, {:quality_validation_failed, results}}
    end
  end
end
