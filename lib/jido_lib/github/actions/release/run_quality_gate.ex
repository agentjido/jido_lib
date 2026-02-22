defmodule Jido.Lib.Github.Actions.Release.RunQualityGate do
  @moduledoc """
  Executes quality bot as a release gate.
  """

  use Jido.Action,
    name: "release_run_quality_gate",
    description: "Run quality gate before release",
    compensation: [max_retries: 0],
    schema: [
      repo_dir: [type: :string, required: true],
      run_id: [type: :string, required: true],
      provider: [type: :atom, default: :codex],
      quality_policy_path: [type: {:or, [:string, nil]}, default: nil],
      sprite_config: [type: {:or, [:map, nil]}, default: nil],
      dry_run: [type: :boolean, default: true],
      apply: [type: :boolean, default: false],
      publish: [type: :boolean, default: false]
    ]

  alias Jido.Lib.Github.Actions.Release.Helpers
  alias Jido.Lib.Github.Agents.QualityBot

  @impl true
  def run(params, _context) do
    quality =
      QualityBot.run_target(params.repo_dir,
        provider: params[:provider] || :codex,
        baseline: "generic_package_qa_v1",
        policy_path: params[:quality_policy_path],
        apply: params[:apply] && params[:publish],
        sprite_config: params[:sprite_config],
        jido: params[:jido] || Jido.Default,
        timeout: 600_000
      )

    failed_count = quality_failed_count(quality)
    quality_ok? = quality[:status] == :completed and failed_count == 0

    if quality_ok? do
      {:ok,
       Helpers.pass_through(params)
       |> Map.put(:quality_result, quality)
       |> Map.put(:warnings, quality[:warnings] || [])}
    else
      {:error,
       {:release_quality_gate_failed,
        %{
          status: quality[:status],
          failed_count: failed_count,
          error: quality[:error],
          result: quality
        }}}
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
