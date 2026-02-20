defmodule Jido.Lib.Github.Actions.PrBot.RunChecks do
  @moduledoc """
  Run required repository checks before branch push and PR creation.
  """

  use Jido.Action,
    name: "run_checks",
    description: "Run required PR gate checks in repo",
    schema: [
      provider: [type: :atom, default: :claude],
      repo_dir: [type: :string, required: true],
      session_id: [type: :string, required: true],
      check_commands: [type: {:list, :string}, default: []],
      timeout: [type: :integer, default: 300_000],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent]
    ]

  alias Jido.Lib.Github.Actions.PrBot.Helpers

  @impl true
  def run(params, _context) do
    agent_mod = params[:shell_agent_mod] || Jido.Shell.Agent
    timeout = params[:timeout] || 300_000
    commands = params[:check_commands] || []

    case run_commands(commands, params, agent_mod, timeout, []) do
      {:ok, results} ->
        {:ok,
         Map.merge(Helpers.pass_through(params), %{
           checks_passed: true,
           check_results: results
         })}

      {:error, cmd, reason, results} ->
        {:error, {:check_failed, cmd, reason, results}}
    end
  end

  defp run_commands([], _params, _agent_mod, _timeout, acc), do: {:ok, Enum.reverse(acc)}

  defp run_commands([cmd | rest], params, agent_mod, timeout, acc) do
    case Helpers.run_in_dir(agent_mod, params.session_id, params.repo_dir, cmd, timeout: timeout) do
      {:ok, output} ->
        run_commands(rest, params, agent_mod, timeout, [
          %{cmd: cmd, status: :ok, output: output} | acc
        ])

      {:error, reason} ->
        results = Enum.reverse([%{cmd: cmd, status: :failed, error: inspect(reason)} | acc])
        {:error, cmd, reason, results}
    end
  end
end
