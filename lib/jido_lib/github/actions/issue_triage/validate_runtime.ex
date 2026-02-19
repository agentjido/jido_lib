defmodule Jido.Lib.Github.Actions.IssueTriage.ValidateRuntime do
  @moduledoc """
  Validate required runtime tooling and env vars inside the Sprite before Claude runs.
  """

  use Jido.Action,
    name: "validate_runtime",
    description: "Validate sprite tooling and ZAI env before Claude probe",
    schema: [
      session_id: [type: :string, required: true],
      timeout: [type: :integer, default: 300_000],
      issue_number: [type: {:or, [:integer, nil]}, default: nil],
      run_id: [type: {:or, [:string, nil]}, default: nil],
      observer_pid: [type: {:or, [:any, nil]}, default: nil],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent]
    ]

  alias Jido.Lib.Github.Actions.IssueTriage.Helpers

  @signal_source "/github/issue_triage/validate_runtime"

  @impl true
  def run(params, _context) do
    agent_mod = params[:shell_agent_mod] || Jido.Shell.Agent
    timeout = params[:timeout] || 30_000

    checks = %{
      gh: tool_present?(agent_mod, params.session_id, "gh", timeout),
      git: tool_present?(agent_mod, params.session_id, "git", timeout),
      claude: tool_present?(agent_mod, params.session_id, "claude", timeout),
      base_url_present: base_url_present?(agent_mod, params.session_id, timeout),
      auth_source: auth_source(agent_mod, params.session_id, timeout)
    }

    redacted_checks = %{
      gh: checks.gh,
      git: checks.git,
      claude: checks.claude,
      base_url_present: checks.base_url_present,
      auth_source: checks.auth_source
    }

    emit_runtime_signal(params[:observer_pid], params, redacted_checks)

    case missing_requirements(redacted_checks) do
      [] ->
        {:ok, Map.merge(Helpers.pass_through(params), %{runtime_checks: redacted_checks})}

      missing ->
        {:error, {:validate_runtime_failed, %{missing: missing, runtime_checks: redacted_checks}}}
    end
  end

  defp tool_present?(agent_mod, session_id, tool, timeout) do
    cmd = "command -v #{tool} >/dev/null 2>&1 && echo present || echo missing"

    case Helpers.run(agent_mod, session_id, cmd, timeout: timeout) do
      {:ok, "present"} -> true
      _ -> false
    end
  end

  defp base_url_present?(agent_mod, session_id, timeout) do
    cmd = "if [ -n \"${ANTHROPIC_BASE_URL:-}\" ]; then echo present; else echo missing; fi"

    case Helpers.run(agent_mod, session_id, cmd, timeout: timeout) do
      {:ok, "present"} -> true
      _ -> false
    end
  end

  defp auth_source(agent_mod, session_id, timeout) do
    cmd = """
    if [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]; then
      echo ANTHROPIC_AUTH_TOKEN
    elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
      echo ANTHROPIC_API_KEY
    elif [ -n "${CLAUDE_CODE_API_KEY:-}" ]; then
      echo CLAUDE_CODE_API_KEY
    else
      echo missing
    fi
    """

    case Helpers.run(agent_mod, session_id, cmd, timeout: timeout) do
      {:ok, "missing"} -> nil
      {:ok, source} when is_binary(source) -> source
      _ -> nil
    end
  end

  defp missing_requirements(checks) do
    []
    |> maybe_add_missing(checks[:gh], :missing_gh)
    |> maybe_add_missing(checks[:git], :missing_git)
    |> maybe_add_missing(checks[:claude], :missing_claude)
    |> maybe_add_missing(checks[:base_url_present], :missing_anthropic_base_url)
    |> maybe_add_missing(not is_nil(checks[:auth_source]), :missing_zai_auth)
  end

  defp maybe_add_missing(acc, true, _reason), do: acc
  defp maybe_add_missing(acc, false, reason), do: acc ++ [reason]

  defp emit_runtime_signal(pid, params, checks) when is_pid(pid) do
    signal =
      Jido.Signal.new!(
        "jido.lib.github.issue_triage.validate_runtime.checked",
        %{
          run_id: params[:run_id],
          issue_number: params[:issue_number],
          session_id: params[:session_id],
          runtime_checks: checks
        },
        source: @signal_source
      )

    send(pid, {:jido_lib_signal, signal})
    :ok
  rescue
    _ -> :ok
  end

  defp emit_runtime_signal(_pid, _params, _checks), do: :ok
end
