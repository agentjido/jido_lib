defmodule Jido.Lib.Github.Actions.Quality.PlanSafeFixes do
  @moduledoc """
  Plans safe fixes for autofix-eligible failed quality findings.
  """

  use Jido.Action,
    name: "quality_plan_safe_fixes",
    description: "Plan safe quality autofixes",
    compensation: [max_retries: 0],
    schema: [
      findings: [type: {:list, :map}, default: []],
      mode: [type: :atom, default: :report],
      apply: [type: :boolean, default: false]
    ]

  alias Jido.Lib.Github.Actions.Quality.Helpers

  @impl true
  def run(params, _context) do
    fix_plan =
      params[:findings]
      |> Enum.filter(fn finding ->
        finding[:status] == :failed and finding[:autofix] == true and
          is_binary(finding[:autofix_strategy])
      end)
      |> Enum.map(fn finding ->
        %{
          id: finding[:id],
          strategy: finding[:autofix_strategy],
          severity: finding[:severity]
        }
      end)

    {:ok, Helpers.pass_through(params) |> Map.put(:fix_plan, fix_plan)}
  end
end
