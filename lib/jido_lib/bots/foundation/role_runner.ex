defmodule Jido.Lib.Bots.Foundation.RoleRunner do
  @moduledoc """
  Shared writer/critic command runner backed by `Jido.Harness.Exec.run_stream/4`.
  """

  alias Jido.Harness.Exec
  alias Jido.Harness.Exec.ProviderRuntime
  alias Jido.Lib.Github.Helpers

  @default_timeout_ms 300_000

  @type role :: :writer | :critic

  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts) when is_list(opts) do
    role = normalize_role(Keyword.get(opts, :role))

    try do
      provider = Helpers.provider_normalize!(Keyword.fetch!(opts, :provider))
      session_id = Keyword.fetch!(opts, :session_id)
      repo_dir = Keyword.fetch!(opts, :repo_dir)
      prompt = Keyword.fetch!(opts, :prompt)

      prompt_file =
        Keyword.get(opts, :prompt_file, default_prompt_file(role, Keyword.get(opts, :run_id)))

      timeout = Keyword.get(opts, :timeout, @default_timeout_ms)
      shell_agent_mod = Keyword.get(opts, :shell_agent_mod, Jido.Shell.Agent)

      shell_session_server_mod =
        Keyword.get(opts, :shell_session_server_mod, Jido.Shell.ShellSessionServer)

      with :ok <- write_prompt(shell_agent_mod, session_id, repo_dir, prompt_file, prompt),
           {:ok, command} <- ProviderRuntime.build_command(provider, :triage, prompt_file),
           {:ok, result} <-
             Exec.run_stream(
               provider,
               session_id,
               repo_dir,
               command: command,
               shell_agent_mod: shell_agent_mod,
               shell_session_server_mod: shell_session_server_mod,
               timeout: timeout
             ),
           :ok <- ensure_success_marker(result) do
        {:ok,
         %{
           role: role,
           provider: provider,
           prompt_file: prompt_file,
           command: command,
           success?: result.success?,
           event_count: result.event_count,
           summary: result.result_text,
           events: result.events,
           output: result.output
         }}
      else
        {:error, reason} ->
          {:error, {:role_runner_failed, role, reason}}
      end
    rescue
      error ->
        {:error, {:role_runner_exception, role, error}}
    end
  end

  defp write_prompt(shell_agent_mod, session_id, repo_dir, prompt_file, prompt)
       when is_atom(shell_agent_mod) and is_binary(session_id) and is_binary(repo_dir) and
              is_binary(prompt_file) and is_binary(prompt) do
    escaped = Helpers.escape_path(prompt_file)
    eof_marker = "JIDO_TRIAGE_CRITIC_PROMPT_EOF"
    command = "cat > #{escaped} << '#{eof_marker}'\n#{prompt}\n#{eof_marker}"

    case Helpers.run_in_dir(shell_agent_mod, session_id, repo_dir, command, timeout: 10_000) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:prompt_write_failed, reason}}
    end
  end

  defp ensure_success_marker(%{success?: true}), do: :ok
  defp ensure_success_marker(_), do: {:error, :missing_success_marker}

  defp default_prompt_file(role, run_id) when role in [:writer, :critic] do
    suffix = run_id || "run"
    "/tmp/jido_#{role}_prompt_#{suffix}.txt"
  end

  defp normalize_role(:writer), do: :writer
  defp normalize_role(:critic), do: :critic
  defp normalize_role("writer"), do: :writer
  defp normalize_role("critic"), do: :critic

  defp normalize_role(other) do
    raise ArgumentError, "invalid role #{inspect(other)}"
  end
end
