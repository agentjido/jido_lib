defmodule Jido.Lib.Github.Helpers do
  @moduledoc false

  require Logger

  alias Jido.Shell.Exec

  @issue_url_pattern ~r{github\.com/([^/]+)/([^/]+)/issues/(\d+)}
  @supported_providers [:claude, :amp, :codex, :gemini]
  @pipeline_keys [
    :issue_url,
    :owner,
    :repo,
    :issue_number,
    :run_id,
    :timeout,
    :jido,
    :keep_workspace,
    :keep_sprite,
    :setup_commands,
    :check_commands,
    :provider,
    :writer_provider,
    :critic_provider,
    :agent_mode,
    :comment_mode,
    :max_revisions,
    :single_pass,
    :codex_phase,
    :codex_fallback_phase,
    :post_comment,
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
    :github_git_auth_ready,
    :runtime_checks,
    :provider_runtime_checks,
    :provider_bootstrap,
    :provider_runtime_ready,
    :role_runtime,
    :role_runtime_ready,
    :sprites_mod,
    :shell_agent_mod,
    :shell_session_mod,
    :shell_session_server_mod,
    :sprite_config,
    :prompt,
    :issue_brief,
    :brief,
    :repos,
    :repo_contexts,
    :output_repo,
    :output_repo_context,
    :output_path,
    :local_output_repo_dir,
    :local_guide_path,
    :workspace_root,
    :sprite_origin,
    :docs_brief,
    :writer_draft_v1,
    :writer_draft_v2,
    :critique_v1,
    :critique_v2,
    :gate_v1,
    :gate_v2,
    :final_decision,
    :decision,
    :needs_revision,
    :iterations_used,
    :final_comment,
    :final_guide,
    :guide_path,
    :artifacts,
    :manifest,
    :started_at,
    :commands,
    :phase,
    :base_sha,
    :branch_name,
    :branch_prefix,
    :investigation,
    :investigation_status,
    :investigation_error,
    :agent_status,
    :agent_summary,
    :agent_error,
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
    :comment_posted,
    :comment_url,
    :comment_error,
    :issue_comment_posted,
    :issue_comment_error,
    :publish,
    :publish_requested,
    :published,
    :teardown_verified,
    :teardown_attempts,
    :warnings,
    :message,
    :status,
    :error,
    # Grounded documentation pipeline keys (shared with DocsWriter)
    :content_metadata,
    :prompt_overrides,
    :brief_body,
    :grounded_sources,
    :grounded_context,
    :execution_trace_v1,
    :execution_trace_v2,
    :execution_feedback,
    :interactive_demo_block,
    :embedded_draft
  ]

  @spec parse_issue_url!(String.t()) :: {String.t(), String.t(), integer()}
  def parse_issue_url!(url) when is_binary(url) do
    case Regex.run(@issue_url_pattern, url) do
      [_, owner, repo, number] -> {owner, repo, String.to_integer(number)}
      _ -> raise ArgumentError, "Invalid GitHub issue URL: #{url}"
    end
  end

  @spec map_get(map(), atom() | String.t(), term()) :: term()
  def map_get(map, key, default \\ nil) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} ->
        value

      :error ->
        case alternate_key(key) do
          nil -> default
          alt_key -> Map.get(map, alt_key, default)
        end
    end
  end

  @spec pass_through(map(), [atom()]) :: map()
  def pass_through(params, extra_keys \\ []) when is_map(params) and is_list(extra_keys) do
    Map.take(params, @pipeline_keys ++ extra_keys)
  end

  @spec provider_supported() :: [atom()]
  def provider_supported, do: @supported_providers

  @spec provider_allowed_string() :: String.t()
  def provider_allowed_string, do: Enum.join(@supported_providers, ", ")

  @spec provider_normalize!(atom() | String.t() | nil) :: atom()
  def provider_normalize!(nil), do: :claude
  def provider_normalize!(provider) when provider in @supported_providers, do: provider

  def provider_normalize!(provider) when is_binary(provider) do
    case provider |> String.trim() |> String.downcase() do
      "claude" -> :claude
      "amp" -> :amp
      "codex" -> :codex
      "gemini" -> :gemini
      _ -> raise_invalid_provider!(provider)
    end
  end

  def provider_normalize!(provider), do: raise_invalid_provider!(provider)

  @spec run_shell(module(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def run_shell(shell_agent_mod, session_id, command, opts \\ [])
      when is_atom(shell_agent_mod) and is_binary(session_id) and is_binary(command) do
    Exec.run(shell_agent_mod, session_id, command, opts)
  end

  @spec run(module(), String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def run(shell_agent_mod, session_id, command, opts \\ [])
      when is_atom(shell_agent_mod) and is_binary(session_id) and is_binary(command) do
    run_shell(shell_agent_mod, session_id, command, opts)
  end

  @spec run_shell_in_dir(module(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def run_shell_in_dir(shell_agent_mod, session_id, cwd, command, opts \\ [])
      when is_atom(shell_agent_mod) and is_binary(session_id) and is_binary(cwd) and
             is_binary(command) do
    Exec.run_in_dir(shell_agent_mod, session_id, cwd, command, opts)
  end

  @spec run_in_dir(module(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def run_in_dir(shell_agent_mod, session_id, cwd, command, opts \\ [])
      when is_atom(shell_agent_mod) and is_binary(session_id) and is_binary(cwd) and
             is_binary(command) do
    run_shell_in_dir(shell_agent_mod, session_id, cwd, command, opts)
  end

  @spec shell_escape_path(String.t()) :: String.t()
  def shell_escape_path(path) when is_binary(path) do
    Exec.escape_path(path)
  end

  @spec escape_path(String.t()) :: String.t()
  def escape_path(path) when is_binary(path) do
    shell_escape_path(path)
  end

  @spec shell_escape(String.t() | atom() | number()) :: String.t()
  def shell_escape(value) do
    value
    |> to_string()
    |> String.replace("'", "'\"'\"'")
    |> then(&"'#{&1}'")
  end

  @spec handle_telemetry([atom()], map(), map(), map()) :: :ok
  def handle_telemetry([:jido_runic, :runnable, status], _measurements, metadata, config),
    do: log_runnable_telemetry(status, metadata, config)

  def handle_telemetry([:jido, :runic, :runnable, status], _measurements, metadata, config),
    do: log_runnable_telemetry(status, metadata, config)

  def handle_telemetry(_event, _measurements, _metadata, _config), do: :ok

  defp log_runnable_telemetry(status, metadata, config) do
    node = metadata[:node]
    name = if node, do: node.name, else: :unknown
    elapsed = System.monotonic_time(:millisecond) - config.start_time
    elapsed_s = Float.round(elapsed / 1000, 1)

    icon = if status == :completed, do: "OK", else: "FAIL"
    label = name |> to_string() |> String.replace("_", " ")

    config.shell.info("[Runic] #{label} #{icon} (#{elapsed_s}s)")
    :ok
  end

  @spec with_logger_level(atom(), (-> term())) :: term()
  def with_logger_level(level, fun) when is_atom(level) and is_function(fun, 0) do
    previous_level = Logger.level()
    previous_agent_level = Logger.get_module_level(Jido.AgentServer)
    Logger.configure(level: level)
    Logger.put_module_level(Jido.AgentServer, :error)

    try do
      fun.()
    after
      Process.sleep(250)
      restore_agent_server_level(previous_agent_level)
      Logger.configure(level: previous_level)
    end
  end

  defp alternate_key(key) when is_atom(key), do: Atom.to_string(key)
  defp alternate_key(_key), do: nil

  defp raise_invalid_provider!(provider) do
    raise ArgumentError,
          "Invalid provider #{inspect(provider)}. Allowed: #{provider_allowed_string()}"
  end

  defp restore_agent_server_level([{Jido.AgentServer, level}]) when is_atom(level),
    do: Logger.put_module_level(Jido.AgentServer, level)

  defp restore_agent_server_level(_), do: Logger.delete_module_level(Jido.AgentServer)
end
