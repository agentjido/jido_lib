defmodule Jido.Lib.Github.Actions.RunRepoCommands do
  @moduledoc """
  Run repository command phases (setup/checks) in a cloned repository.
  """

  use Jido.Action,
    name: "run_repo_commands",
    description: "Run setup/check command batches in repo",
    compensation: [max_retries: 0],
    schema: [
      phase: [type: {:or, [:atom, nil]}, default: nil],
      fail_mode: [type: :atom, default: :halt_on_first],
      return_results: [type: :boolean, default: false],
      provider: [type: :atom, default: :claude],
      single_pass: [type: :boolean, default: false],
      repo_dir: [type: :string, required: true],
      session_id: [type: :string, required: true],
      commands: [type: {:list, :string}, default: []],
      setup_commands: [type: {:list, :string}, default: []],
      check_commands: [type: {:list, :string}, default: []],
      timeout: [type: :integer, default: 300_000],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent]
    ]

  alias Jido.Lib.Github.Helpers

  @impl true
  def run(params, _context) do
    phase = normalize_phase(params[:phase], params)
    fail_mode = normalize_fail_mode(params[:fail_mode])
    commands = commands_for_phase(phase, params)
    timeout = params[:timeout] || 300_000
    agent_mod = params[:shell_agent_mod] || Jido.Shell.Agent

    case run_commands(commands, params, agent_mod, timeout, fail_mode, []) do
      {:ok, results} ->
        {:ok, success_output(phase, params, results)}

      {:error, cmd, reason, results} ->
        {:error, failure_output(phase, cmd, reason, results)}
    end
  end

  defp success_output(:setup, params, results) do
    output = Helpers.pass_through(params)

    if params[:return_results] do
      Map.put(output, :setup_results, results)
    else
      output
    end
  end

  defp success_output(:checks, params, results) do
    output =
      Map.merge(Helpers.pass_through(params), %{checks_passed: true})

    if params[:return_results] do
      Map.put(output, :check_results, results)
    else
      output
    end
  end

  defp failure_output(:setup, cmd, reason, _results), do: {:setup_failed, cmd, reason}
  defp failure_output(:checks, cmd, reason, results), do: {:check_failed, cmd, reason, results}

  defp run_commands([], _params, _agent_mod, _timeout, _fail_mode, acc),
    do: {:ok, Enum.reverse(acc)}

  defp run_commands([cmd | rest], params, agent_mod, timeout, fail_mode, acc) do
    case Helpers.run_in_dir(agent_mod, params.session_id, params.repo_dir, cmd, timeout: timeout) do
      {:ok, output} ->
        run_commands(rest, params, agent_mod, timeout, fail_mode, [
          %{cmd: cmd, status: :ok, output: output} | acc
        ])

      {:error, reason} ->
        next_acc = [%{cmd: cmd, status: :failed, error: inspect(reason)} | acc]
        handle_command_failure(fail_mode, rest, params, agent_mod, timeout, next_acc, cmd, reason)
    end
  end

  defp handle_command_failure(
         :halt_on_first,
         _rest,
         _params,
         _agent_mod,
         _timeout,
         next_acc,
         cmd,
         reason
       ) do
    {:error, cmd, reason, Enum.reverse(next_acc)}
  end

  defp handle_command_failure(
         :collect_then_fail,
         rest,
         params,
         agent_mod,
         timeout,
         next_acc,
         cmd,
         reason
       ) do
    case run_commands(rest, params, agent_mod, timeout, :collect_then_fail, next_acc) do
      {:ok, results} ->
        {:error, cmd, reason, results}

      {:error, first_cmd, first_reason, results} ->
        {:error, first_cmd, first_reason, results}
    end
  end

  defp normalize_phase(:setup, _params), do: :setup
  defp normalize_phase(:checks, _params), do: :checks
  defp normalize_phase(nil, params), do: infer_phase(params)

  defp normalize_phase(other, _params),
    do: raise(ArgumentError, "Invalid phase: #{inspect(other)}")

  defp normalize_fail_mode(:halt_on_first), do: :halt_on_first
  defp normalize_fail_mode(:collect_then_fail), do: :collect_then_fail

  defp normalize_fail_mode(other),
    do: raise(ArgumentError, "Invalid fail_mode: #{inspect(other)}")

  defp infer_phase(params) when is_map(params) do
    if is_binary(params[:commit_sha]) and params[:commit_sha] != "" do
      :checks
    else
      :setup
    end
  end

  defp commands_for_phase(:setup, params) do
    first_non_empty_list([params[:commands], params[:setup_commands]])
  end

  defp commands_for_phase(:checks, params) do
    first_non_empty_list([params[:commands], params[:check_commands]])
  end

  defp first_non_empty_list(candidates) when is_list(candidates) do
    Enum.find_value(candidates, [], fn
      list when is_list(list) and list != [] -> list
      _ -> nil
    end)
  end
end
