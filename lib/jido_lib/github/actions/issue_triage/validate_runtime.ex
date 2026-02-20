defmodule Jido.Lib.Github.Actions.IssueTriage.ValidateRuntime do
  @moduledoc """
  Validate shared and provider-specific runtime requirements inside Sprite.
  """

  use Jido.Action,
    name: "validate_runtime",
    description: "Validate shared + provider runtime requirements",
    schema: [
      provider: [type: :atom, default: :claude],
      session_id: [type: :string, required: true],
      repo_dir: [type: {:or, [:string, nil]}, default: nil],
      timeout: [type: :integer, default: 300_000],
      issue_number: [type: {:or, [:integer, nil]}, default: nil],
      run_id: [type: {:or, [:string, nil]}, default: nil],
      observer_pid: [type: {:or, [:any, nil]}, default: nil],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent]
    ]

  alias Jido.Harness.Exec
  alias Jido.Lib.Github.Actions.IssueTriage.Helpers

  @signal_source "/github/issue_triage/validate_runtime"

  @impl true
  def run(params, _context) do
    provider = params[:provider] || :claude
    agent_mod = params[:shell_agent_mod] || Jido.Shell.Agent
    timeout = params[:timeout] || 30_000
    cwd = params[:repo_dir]

    with {:ok, shared_checks} <-
           Exec.validate_shared_runtime(
             params.session_id,
             shell_agent_mod: agent_mod,
             timeout: timeout
           ),
         {:ok, provider_checks} <-
           Exec.validate_provider_runtime(
             provider,
             params.session_id,
             shell_agent_mod: agent_mod,
             timeout: timeout,
             cwd: cwd
           ) do
      checks = %{
        shared: shared_checks,
        provider: provider_checks.checks,
        provider_name: provider
      }

      emit_runtime_signal(params[:observer_pid], params, checks)

      {:ok,
       Map.merge(Helpers.pass_through(params), %{
         runtime_checks: checks,
         provider_runtime_checks: provider_checks.checks
       })}
    else
      {:error, reason} ->
        normalized = normalize_error(reason, provider)
        emit_runtime_signal(params[:observer_pid], params, normalized)
        {:error, {:validate_runtime_failed, normalized}}
    end
  end

  defp normalize_error(%Jido.Harness.Error.ExecutionFailureError{details: details}, provider)
       when is_map(details) do
    %{
      provider: provider,
      error: details[:code] || :runtime_validation_failed,
      missing: details[:missing] || [],
      checks: details[:checks]
    }
  end

  defp normalize_error(other, provider) do
    %{
      provider: provider,
      error: inspect(other),
      missing: [],
      checks: nil
    }
  end

  defp emit_runtime_signal(pid, params, checks) when is_pid(pid) do
    signal =
      Jido.Signal.new!(
        "jido.lib.github.issue_triage.validate_runtime.checked",
        %{
          run_id: params[:run_id],
          issue_number: params[:issue_number],
          session_id: params[:session_id],
          provider: params[:provider] || :claude,
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
