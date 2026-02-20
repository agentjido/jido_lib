defmodule Jido.Lib.Github.ResultMaps do
  @moduledoc false

  alias Jido.Lib.Github.Helpers

  @spec triage_result(map(), map(), [map()]) :: map()
  def triage_result(intake, final, productions)
      when is_map(intake) and is_map(final) and is_list(productions) do
    provider =
      result_value(final, productions, :provider, Helpers.map_get(intake, :provider, :claude))

    %{
      status: result_value(final, productions, :status, :completed),
      run_id: result_value(final, productions, :run_id, Helpers.map_get(intake, :run_id)),
      provider: provider,
      owner: result_value(final, productions, :owner, Helpers.map_get(intake, :owner)),
      repo: result_value(final, productions, :repo, Helpers.map_get(intake, :repo)),
      issue_number:
        result_value(final, productions, :issue_number, Helpers.map_get(intake, :issue_number)),
      issue_url:
        result_value(final, productions, :issue_url, Helpers.map_get(intake, :issue_url)),
      message: result_value(final, productions, :message, nil),
      investigation: result_value(final, productions, :investigation, nil),
      investigation_status: result_value(final, productions, :investigation_status, nil),
      investigation_error: result_value(final, productions, :investigation_error, nil),
      agent_status: result_value(final, productions, :agent_status, nil),
      agent_summary: result_value(final, productions, :agent_summary, nil),
      agent_error: result_value(final, productions, :agent_error, nil),
      comment_posted: result_value(final, productions, :comment_posted, nil),
      comment_url: result_value(final, productions, :comment_url, nil),
      comment_error: result_value(final, productions, :comment_error, nil),
      sprite_name: result_value(final, productions, :sprite_name, nil),
      session_id: result_value(final, productions, :session_id, nil),
      workspace_dir: result_value(final, productions, :workspace_dir, nil),
      teardown_verified: result_value(final, productions, :teardown_verified, nil),
      teardown_attempts: result_value(final, productions, :teardown_attempts, nil),
      warnings: result_value(final, productions, :warnings, nil),
      runtime_checks: result_value(final, productions, :runtime_checks, nil),
      provider_runtime_checks: result_value(final, productions, :provider_runtime_checks, nil),
      provider_bootstrap: result_value(final, productions, :provider_bootstrap, nil),
      error: result_value(final, productions, :error, nil)
    }
  end

  @spec pr_result(map(), map(), [map()]) :: map()
  def pr_result(intake, final, productions)
      when is_map(intake) and is_map(final) and is_list(productions) do
    provider =
      result_value(final, productions, :provider, Helpers.map_get(intake, :provider, :claude))

    %{
      status: result_value(final, productions, :status, :completed),
      run_id: result_value(final, productions, :run_id, Helpers.map_get(intake, :run_id)),
      provider: provider,
      owner: result_value(final, productions, :owner, Helpers.map_get(intake, :owner)),
      repo: result_value(final, productions, :repo, Helpers.map_get(intake, :repo)),
      issue_number:
        result_value(final, productions, :issue_number, Helpers.map_get(intake, :issue_number)),
      issue_url:
        result_value(final, productions, :issue_url, Helpers.map_get(intake, :issue_url)),
      base_branch:
        result_value(final, productions, :base_branch, Helpers.map_get(intake, :base_branch)),
      branch_name: result_value(final, productions, :branch_name, nil),
      agent_status: result_value(final, productions, :agent_status, nil),
      agent_summary: result_value(final, productions, :agent_summary, nil),
      agent_error: result_value(final, productions, :agent_error, nil),
      commit_sha: result_value(final, productions, :commit_sha, nil),
      checks_passed: result_value(final, productions, :checks_passed, nil),
      check_results: result_value(final, productions, :check_results, nil),
      pr_created: result_value(final, productions, :pr_created, nil),
      pr_number: result_value(final, productions, :pr_number, nil),
      pr_url: result_value(final, productions, :pr_url, nil),
      pr_title: result_value(final, productions, :pr_title, nil),
      issue_comment_posted: result_value(final, productions, :issue_comment_posted, nil),
      issue_comment_error: result_value(final, productions, :issue_comment_error, nil),
      sprite_name: result_value(final, productions, :sprite_name, nil),
      session_id: result_value(final, productions, :session_id, nil),
      workspace_dir: result_value(final, productions, :workspace_dir, nil),
      teardown_verified: result_value(final, productions, :teardown_verified, nil),
      teardown_attempts: result_value(final, productions, :teardown_attempts, nil),
      warnings: result_value(final, productions, :warnings, nil),
      runtime_checks: result_value(final, productions, :runtime_checks, nil),
      provider_runtime_checks: result_value(final, productions, :provider_runtime_checks, nil),
      provider_bootstrap: result_value(final, productions, :provider_bootstrap, nil),
      message: result_value(final, productions, :message, nil),
      error: result_value(final, productions, :error, nil)
    }
  end

  @spec default_pr_result(map()) :: map()
  def default_pr_result(intake) when is_map(intake) do
    %{
      status: :failed,
      run_id: Helpers.map_get(intake, :run_id),
      provider: Helpers.map_get(intake, :provider, :claude),
      owner: Helpers.map_get(intake, :owner),
      repo: Helpers.map_get(intake, :repo),
      issue_number: Helpers.map_get(intake, :issue_number),
      issue_url: Helpers.map_get(intake, :issue_url),
      base_branch: Helpers.map_get(intake, :base_branch),
      branch_name: nil,
      agent_status: nil,
      agent_summary: nil,
      agent_error: nil,
      commit_sha: nil,
      checks_passed: nil,
      check_results: nil,
      pr_created: nil,
      pr_number: nil,
      pr_url: nil,
      pr_title: nil,
      issue_comment_posted: nil,
      issue_comment_error: nil,
      sprite_name: nil,
      session_id: nil,
      workspace_dir: nil,
      teardown_verified: nil,
      teardown_attempts: nil,
      warnings: nil,
      runtime_checks: nil,
      provider_runtime_checks: nil,
      provider_bootstrap: nil,
      message: nil,
      error: nil
    }
  end

  @spec result_value(map(), [map()], atom(), term()) :: term()
  def result_value(final, productions, key, default)
      when is_map(final) and is_list(productions) and is_atom(key) do
    case Helpers.map_get(final, key) do
      nil ->
        case production_value(productions, key) do
          nil -> default
          value -> value
        end

      value ->
        value
    end
  end

  @spec production_value([map()], atom()) :: term()
  def production_value(productions, key) when is_list(productions) and is_atom(key) do
    Enum.find_value(Enum.reverse(productions), fn
      value when is_map(value) -> Helpers.map_get(value, key)
      _ -> nil
    end)
  end
end
