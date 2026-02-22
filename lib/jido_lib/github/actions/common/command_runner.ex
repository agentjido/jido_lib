defmodule Jido.Lib.Github.Actions.Common.CommandRunner do
  @moduledoc """
  Shared command runner with dry-run and mutation-aware gating.
  """

  alias Jido.Lib.Github.Actions.Common.MutationGuard
  alias Jido.Lib.Github.Helpers

  @mutating_patterns [
    "git commit",
    "git push",
    "git tag",
    "gh release create",
    "mix hex.publish",
    "sed -i",
    "perl -pi"
  ]

  @spec run_local(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_local(command, opts \\ []) when is_binary(command) and is_list(opts) do
    repo_dir = Keyword.get(opts, :repo_dir, ".")
    params = Keyword.get(opts, :params, %{})
    allow_mutation? = MutationGuard.mutation_allowed?(params)

    if mutating_command?(command) and not allow_mutation? do
      {:ok, %{status: :skipped, command: command, reason: :dry_run, output: ""}}
    else
      run_local!(command, repo_dir)
    end
  end

  @spec run_in_session(module(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def run_in_session(shell_agent_mod, session_id, repo_dir, command, opts \\ [])
      when is_atom(shell_agent_mod) and is_binary(session_id) and is_binary(repo_dir) and
             is_binary(command) and is_list(opts) do
    params = Keyword.get(opts, :params, %{})
    timeout = Keyword.get(opts, :timeout, 300_000)

    if mutating_command?(command) and not MutationGuard.mutation_allowed?(params) do
      {:ok, %{status: :skipped, command: command, reason: :dry_run, output: ""}}
    else
      case Helpers.run_in_dir(shell_agent_mod, session_id, repo_dir, command, timeout: timeout) do
        {:ok, output} -> {:ok, %{status: :ok, command: command, output: output}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @spec run_check_commands([String.t()], String.t(), map()) :: {:ok, [map()]} | {:error, [map()]}
  def run_check_commands(commands, repo_dir, params)
      when is_list(commands) and is_binary(repo_dir) and is_map(params) do
    Enum.reduce_while(commands, {:ok, []}, fn command, {:ok, acc} ->
      case run_local(command, repo_dir: repo_dir, params: params) do
        {:ok, result} ->
          {:cont, {:ok, [result | acc]}}

        {:error, reason} ->
          result = %{status: :error, command: command, reason: inspect(reason), output: ""}
          {:halt, {:error, Enum.reverse([result | acc])}}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      {:error, results} -> {:error, results}
    end
  end

  @spec mutating_command?(String.t()) :: boolean()
  def mutating_command?(command) when is_binary(command) do
    Enum.any?(@mutating_patterns, &String.contains?(command, &1))
  end

  defp run_local!(command, repo_dir) do
    wrapped = "cd #{Helpers.escape_path(repo_dir)} && #{command}"

    case System.cmd("bash", ["-lc", wrapped], stderr_to_stdout: true) do
      {output, 0} -> {:ok, %{status: :ok, command: command, output: output}}
      {output, code} -> {:error, {:command_failed, code, output}}
    end
  rescue
    error -> {:error, {:command_error, Exception.message(error)}}
  end
end
