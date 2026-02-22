defmodule Jido.Lib.Github.Actions.Release.RunReleaseChecks do
  @moduledoc """
  Runs release validation checks.
  """

  use Jido.Action,
    name: "release_run_checks",
    description: "Run release checks",
    compensation: [max_retries: 0],
    schema: [
      repo_dir: [type: :string, required: true],
      dry_run: [type: :boolean, default: true],
      publish: [type: :boolean, default: false]
    ]

  alias Jido.Lib.Github.Actions.Common.CommandRunner
  alias Jido.Lib.Github.Actions.Release.Helpers

  @commands ["mix quality"]

  @impl true
  def run(params, _context) do
    case CommandRunner.run_check_commands(
           @commands,
           params.repo_dir,
           Map.put(params, :apply, true)
         ) do
      {:ok, results} ->
        {:ok, Helpers.pass_through(params) |> Map.put(:release_checks, results)}

      {:error, results} ->
        {:error, {:release_checks_failed, results}}
    end
  end
end
