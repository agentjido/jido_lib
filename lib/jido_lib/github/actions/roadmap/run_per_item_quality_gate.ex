defmodule Jido.Lib.Github.Actions.Roadmap.RunPerItemQualityGate do
  @moduledoc """
  Runs Quality Bot as a gate for roadmap queue output.
  """

  use Jido.Action,
    name: "roadmap_run_per_item_quality_gate",
    description: "Run roadmap quality gate",
    compensation: [max_retries: 0],
    schema: [
      repo_dir: [type: :string, required: true],
      provider: [type: :atom, default: :codex],
      baseline: [type: :string, default: "generic_package_qa_v1"],
      quality_policy_path: [type: {:or, [:string, nil]}, default: nil],
      sprite_config: [type: {:or, [:map, nil]}, default: nil],
      apply: [type: :boolean, default: false],
      queue_results: [type: {:list, :map}, default: []]
    ]

  alias Jido.Lib.Github.Actions.Roadmap.Helpers
  alias Jido.Lib.Github.Agents.QualityBot

  @impl true
  def run(params, _context) do
    if params.queue_results == [] do
      {:ok,
       Helpers.pass_through(params)
       |> Map.put(:quality_gate, %{status: :skipped, reason: :empty_queue, passed: true})}
    else
      quality_result =
        QualityBot.run_target(params.repo_dir,
          provider: params[:provider] || :codex,
          baseline: params[:baseline] || "generic_package_qa_v1",
          policy_path: params[:quality_policy_path],
          apply: false,
          sprite_config: params[:sprite_config],
          jido: params[:jido] || Jido.Default,
          timeout: 600_000,
          debug: false
        )

      failed_count = quality_failed_count(quality_result)
      passed = quality_result[:status] == :completed and failed_count == 0

      quality_gate = %{
        passed: passed,
        status: quality_result[:status],
        failed_count: failed_count,
        result: quality_result
      }

      if passed or params[:apply] != true do
        {:ok, Helpers.pass_through(params) |> Map.put(:quality_gate, quality_gate)}
      else
        {:error, {:roadmap_quality_gate_failed, quality_gate}}
      end
    end
  end

  defp quality_failed_count(%{summary: summary}) when is_map(summary) do
    case summary do
      %{failed: count} when is_integer(count) -> count
      %{"failed" => count} when is_integer(count) -> count
      _ -> 0
    end
  end

  defp quality_failed_count(_), do: 0
end
