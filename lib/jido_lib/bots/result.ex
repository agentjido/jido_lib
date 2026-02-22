defmodule Jido.Lib.Bots.Result do
  @moduledoc """
  Shared normalized result helpers for bot workflows.
  """

  alias Jido.Lib.Github.Helpers

  @spec meta_from_intake(map()) :: map()
  def meta_from_intake(intake) when is_map(intake) do
    %{
      request_id: Helpers.map_get(intake, :request_id, Helpers.map_get(intake, :run_id)),
      run_id: Helpers.map_get(intake, :run_id),
      provider: Helpers.map_get(intake, :provider, :codex),
      owner: Helpers.map_get(intake, :owner),
      repo: Helpers.map_get(intake, :repo),
      issue_number: Helpers.map_get(intake, :issue_number),
      session_id: Helpers.map_get(intake, :session_id)
    }
  end

  @spec from_run(atom(), map(), map(), map()) :: map()
  def from_run(kind, intake, run, final)
      when is_atom(kind) and is_map(intake) and is_map(run) and is_map(final) do
    run_id = latest_value(run, final, :run_id, Helpers.map_get(intake, :run_id))
    provider = latest_value(run, final, :provider, Helpers.map_get(intake, :provider, :codex))
    target = latest_value(run, final, :target, Helpers.map_get(intake, :target))
    owner = latest_value(run, final, :owner, Helpers.map_get(intake, :owner))
    repo = latest_value(run, final, :repo, Helpers.map_get(intake, :repo))
    artifacts = latest_value(run, final, :artifacts, [])
    warnings = latest_value(run, final, :warnings, [])
    summary = latest_value(run, final, :summary)
    findings = latest_value(run, final, :findings)
    outputs = latest_value(run, final, :outputs, %{})

    %{
      bot: kind,
      status: run.status,
      error: run.error,
      run_id: run_id,
      provider: provider,
      target: target,
      owner: owner,
      repo: repo,
      artifacts: artifacts,
      warnings: warnings,
      summary: summary,
      findings: findings,
      outputs: outputs,
      productions: run.productions,
      facts: run.facts,
      failures: run.failures,
      events: run.events,
      pid: run.pid
    }
  end

  @spec fallback(atom(), map(), term()) :: map()
  def fallback(kind, intake, reason) when is_atom(kind) and is_map(intake) do
    %{
      bot: kind,
      status: :error,
      error: reason,
      run_id: Helpers.map_get(intake, :run_id),
      provider: Helpers.map_get(intake, :provider, :codex),
      target: Helpers.map_get(intake, :target),
      owner: Helpers.map_get(intake, :owner),
      repo: Helpers.map_get(intake, :repo),
      artifacts: [],
      warnings: [],
      summary: nil,
      findings: nil,
      outputs: %{},
      productions: [],
      facts: [],
      failures: [],
      events: [],
      pid: nil
    }
  end

  defp latest_value(run, final, key, default \\ nil)
       when is_map(run) and is_map(final) and is_atom(key) do
    case production_value(run.productions, key) do
      nil -> Helpers.map_get(final, key, default)
      value -> value
    end
  end

  defp production_value(productions, key) when is_list(productions) and is_atom(key) do
    Enum.find_value(Enum.reverse(productions), fn
      map when is_map(map) -> Helpers.map_get(map, key)
      _ -> nil
    end)
  end
end
