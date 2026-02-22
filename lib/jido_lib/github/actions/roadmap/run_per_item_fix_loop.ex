defmodule Jido.Lib.Github.Actions.Roadmap.RunPerItemFixLoop do
  @moduledoc """
  Runs a bounded quality safe-fix loop for roadmap output.
  """

  use Jido.Action,
    name: "roadmap_run_per_item_fix_loop",
    description: "Run bounded roadmap fix loop",
    compensation: [max_retries: 0],
    schema: [
      repo_dir: [type: :string, required: true],
      provider: [type: :atom, default: :codex],
      baseline: [type: :string, default: "generic_package_qa_v1"],
      quality_policy_path: [type: {:or, [:string, nil]}, default: nil],
      sprite_config: [type: {:or, [:map, nil]}, default: nil],
      apply: [type: :boolean, default: false],
      max_fix_attempts: [type: :integer, default: 2],
      quality_gate: [type: {:or, [:map, nil]}, default: nil]
    ]

  alias Jido.Lib.Github.Actions.Roadmap.Helpers
  alias Jido.Lib.Github.Agents.QualityBot

  @impl true
  def run(params, _context) do
    cond do
      params[:apply] != true ->
        {:ok,
         Helpers.pass_through(params) |> Map.put(:fix_loop, %{status: :skipped, attempts: 0})}

      quality_gate_passed?(params[:quality_gate]) ->
        {:ok,
         Helpers.pass_through(params)
         |> Map.put(:fix_loop, %{status: :skipped, reason: :quality_already_green, attempts: 0})}

      true ->
        run_fix_attempts(params, params[:max_fix_attempts] || 2, 1, [])
    end
  end

  defp run_fix_attempts(_params, max_attempts, attempt, attempts) when attempt > max_attempts do
    {:error,
     {:roadmap_fix_loop_failed,
      %{status: :failed, attempts: Enum.reverse(attempts), reason: :max_attempts_exhausted}}}
  end

  defp run_fix_attempts(params, max_attempts, attempt, attempts) do
    result =
      QualityBot.run_target(params.repo_dir,
        provider: params[:provider] || :codex,
        baseline: params[:baseline] || "generic_package_qa_v1",
        policy_path: params[:quality_policy_path],
        apply: true,
        sprite_config: params[:sprite_config],
        jido: params[:jido] || Jido.Default,
        timeout: 600_000,
        debug: false
      )

    next_attempts = [%{attempt: attempt, result: result} | attempts]
    failed_count = quality_failed_count(result)
    passed = result[:status] == :completed and failed_count == 0

    if passed do
      {:ok,
       Helpers.pass_through(params)
       |> Map.put(:fix_loop, %{
         status: :completed,
         attempts: Enum.reverse(next_attempts),
         result: result
       })}
    else
      run_fix_attempts(params, max_attempts, attempt + 1, next_attempts)
    end
  end

  defp quality_gate_passed?(%{passed: true}), do: true
  defp quality_gate_passed?(_), do: false

  defp quality_failed_count(%{summary: summary}) when is_map(summary) do
    case summary do
      %{failed: count} when is_integer(count) -> count
      %{"failed" => count} when is_integer(count) -> count
      _ -> 0
    end
  end

  defp quality_failed_count(_), do: 0
end
