defmodule Jido.Lib.Github.Actions.IssueTriage.Helpers do
  @moduledoc false

  @pipeline_keys [
    :session_id,
    :observer_pid,
    :workspace_dir,
    :run_id,
    :owner,
    :repo,
    :issue_number,
    :issue_url,
    :timeout,
    :keep_workspace,
    :keep_sprite,
    :setup_commands,
    :repo_dir,
    :issue_title,
    :issue_body,
    :issue_labels,
    :issue_author,
    :sprite_name,
    :github_auth_ready,
    :runtime_checks,
    :investigation,
    :investigation_status,
    :investigation_error,
    :comment_posted,
    :comment_url,
    :comment_error,
    :teardown_verified,
    :teardown_attempts,
    :warnings,
    :prompt,
    :sprites_mod,
    :shell_agent_mod,
    :shell_session_mod,
    :sprite_config
  ]

  @spec pass_through(map(), [atom()]) :: map()
  def pass_through(params, extra_keys \\ []) when is_map(params) and is_list(extra_keys) do
    Map.take(params, @pipeline_keys ++ extra_keys)
  end

  @spec run(module(), String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def run(shell_agent_mod, session_id, command, opts \\ [])
      when is_atom(shell_agent_mod) and is_binary(session_id) and is_binary(command) do
    timeout = Keyword.get(opts, :timeout, 60_000)

    case shell_agent_mod.run(session_id, command, timeout: timeout) do
      {:ok, output} -> {:ok, String.trim(output)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec run_in_dir(module(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def run_in_dir(shell_agent_mod, session_id, cwd, command, opts \\ [])
      when is_atom(shell_agent_mod) and is_binary(session_id) and is_binary(cwd) and
             is_binary(command) do
    wrapped = "cd #{escape_path(cwd)} && #{command}"
    run(shell_agent_mod, session_id, wrapped, opts)
  end

  @spec escape_path(String.t()) :: String.t()
  def escape_path(path) when is_binary(path) do
    "'#{String.replace(path, "'", "'\\''")}'"
  end
end
