defmodule Jido.Lib.Github.Actions.PrBot.Helpers do
  @moduledoc false

  @pipeline_keys [
    :issue_url,
    :owner,
    :repo,
    :issue_number,
    :run_id,
    :timeout,
    :keep_sprite,
    :setup_commands,
    :check_commands,
    :base_branch,
    :branch_prefix,
    :observer_pid,
    :session_id,
    :workspace_dir,
    :repo_dir,
    :issue_title,
    :issue_body,
    :issue_labels,
    :issue_author,
    :sprite_name,
    :github_auth_ready,
    :runtime_checks,
    :sprites_mod,
    :shell_agent_mod,
    :shell_session_mod,
    :sprite_config,
    :base_sha,
    :branch_name,
    :claude_status,
    :claude_summary,
    :commit_sha,
    :commits_since_base,
    :fallback_commit_used,
    :checks_passed,
    :check_results,
    :branch_pushed,
    :pr_created,
    :pr_number,
    :pr_url,
    :pr_title,
    :issue_comment_posted,
    :issue_comment_error,
    :teardown_verified,
    :teardown_attempts,
    :warnings,
    :message,
    :error
  ]

  @spec pass_through(map(), [atom()]) :: map()
  def pass_through(params, extra_keys \\ []) when is_map(params) and is_list(extra_keys) do
    Map.take(params, @pipeline_keys ++ extra_keys)
  end

  @spec run(module(), String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def run(shell_agent_mod, session_id, command, opts \\ [])
      when is_atom(shell_agent_mod) and is_binary(session_id) and is_binary(command) do
    Jido.Shell.Exec.run(shell_agent_mod, session_id, command, opts)
  end

  @spec run_in_dir(module(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def run_in_dir(shell_agent_mod, session_id, cwd, command, opts \\ [])
      when is_atom(shell_agent_mod) and is_binary(session_id) and is_binary(cwd) and
             is_binary(command) do
    Jido.Shell.Exec.run_in_dir(shell_agent_mod, session_id, cwd, command, opts)
  end

  @spec escape_path(String.t()) :: String.t()
  def escape_path(path) when is_binary(path) do
    Jido.Shell.Exec.escape_path(path)
  end

  @spec shell_escape(String.t() | atom() | number()) :: String.t()
  def shell_escape(value) do
    value
    |> to_string()
    |> String.replace("'", "'\"'\"'")
    |> then(&"'#{&1}'")
  end

  @spec map_get(map(), atom(), term()) :: term()
  def map_get(map, key, default \\ nil) when is_map(map) and is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key), default)
    end
  end
end
