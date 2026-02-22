defmodule Jido.Lib.Github.Actions.Quality.EvaluateChecks do
  @moduledoc """
  Evaluates policy checks and produces deterministic findings.
  """

  use Jido.Action,
    name: "quality_evaluate_checks",
    description: "Evaluate baseline quality rules",
    compensation: [max_retries: 0],
    schema: [
      repo_dir: [type: :string, required: true],
      policy: [type: :map, required: true],
      facts: [type: :map, required: true],
      mode: [type: :atom, default: :report],
      apply: [type: :boolean, default: false]
    ]

  alias Jido.Lib.Github.Actions.Common.CommandRunner
  alias Jido.Lib.Github.Actions.Quality.Helpers

  @impl true
  def run(params, _context) do
    rules = Map.get(params.policy, :rules, [])

    findings =
      rules
      |> Enum.filter(&is_map/1)
      |> Enum.map(&evaluate_rule(&1, params))

    summary = %{
      total_rules: length(findings),
      passed: Enum.count(findings, &(&1.status == :passed)),
      failed: Enum.count(findings, &(&1.status == :failed)),
      skipped: Enum.count(findings, &(&1.status == :skipped))
    }

    {:ok,
     Helpers.pass_through(params)
     |> Map.put(:findings, findings)
     |> Map.put(:summary, summary)}
  end

  defp evaluate_rule(rule, params) do
    check = Map.get(rule, :check, %{})

    base = %{
      id: Map.get(rule, :id, "unknown_rule"),
      severity: Map.get(rule, :severity, "info"),
      description: Map.get(rule, :description, ""),
      docs_ref: Map.get(rule, :docs_ref),
      autofix: Map.get(rule, :autofix, false),
      autofix_strategy: Map.get(rule, :autofix_strategy),
      status: :skipped,
      details: nil
    }

    case Map.get(check, :kind, "command") do
      "command" -> evaluate_command_rule(base, rule, params)
      "file_exists" -> evaluate_file_exists_rule(base, check, params)
      "regex" -> evaluate_regex_rule(base, check, params)
      other -> %{base | status: :skipped, details: "Unsupported check kind: #{inspect(other)}"}
    end
  end

  defp evaluate_command_rule(base, rule, params) do
    command = rule |> Map.get(:check, %{}) |> Map.get(:command)

    case valid_command(command) do
      false ->
        %{base | status: :skipped, details: "Missing command"}

      true ->
        evaluate_command_execution(base, command, params.repo_dir)
    end
  end

  defp evaluate_command_execution(base, command, repo_dir) do
    case CommandRunner.run_local(command,
           repo_dir: repo_dir,
           params: %{mode: :report, apply: false}
         ) do
      {:ok, %{status: :ok, output: output}} ->
        %{base | status: :passed, details: trim_output(output)}

      {:ok, %{output: output}} ->
        %{base | status: :failed, details: trim_output(output)}

      {:error, reason} ->
        %{base | status: :failed, details: inspect(reason)}
    end
  end

  defp valid_command(command) when is_binary(command), do: command != ""
  defp valid_command(_), do: false

  defp evaluate_file_exists_rule(base, check, params) do
    path = Map.get(check, :path, "")

    if is_binary(path) and path != "" do
      full_path = Path.join(params.repo_dir, path)

      if File.exists?(full_path) do
        %{base | status: :passed, details: path}
      else
        %{base | status: :failed, details: "Missing file: #{path}"}
      end
    else
      %{base | status: :skipped, details: "Missing path"}
    end
  end

  defp evaluate_regex_rule(base, check, params) do
    path = Map.get(check, :path, "")
    pattern = Map.get(check, :pattern, "")

    with true <- is_binary(path) and path != "",
         true <- is_binary(pattern) and pattern != "",
         {:ok, content} <- File.read(Path.join(params.repo_dir, path)),
         {:ok, regex} <- Regex.compile(pattern) do
      if Regex.match?(regex, content) do
        %{base | status: :passed, details: path}
      else
        %{base | status: :failed, details: "Regex not matched in #{path}"}
      end
    else
      false -> %{base | status: :skipped, details: "Invalid regex rule inputs"}
      {:error, reason} -> %{base | status: :failed, details: inspect(reason)}
    end
  end

  defp trim_output(output) when is_binary(output) do
    output
    |> String.trim()
    |> String.slice(0, 500)
  end

  defp trim_output(_), do: ""
end
