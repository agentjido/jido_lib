defmodule Jido.Lib.Github.Actions.IssueTriage.RunCodingAgent do
  @moduledoc """
  Run the selected coding agent in triage mode for investigation.
  """

  use Jido.Action,
    name: "run_coding_agent",
    description: "Run provider triage command in repository",
    schema: [
      provider: [type: :atom, default: :claude],
      repo_dir: [type: :string, required: true],
      session_id: [type: :string, required: true],
      timeout: [type: :integer, default: 300_000],
      prompt: [type: {:or, [:string, nil]}, default: nil],
      issue_title: [type: {:or, [:string, nil]}, default: nil],
      issue_body: [type: {:or, [:string, nil]}, default: nil],
      issue_labels: [type: {:list, :string}, default: []],
      issue_number: [type: :integer, required: true],
      run_id: [type: {:or, [:string, nil]}, default: nil],
      observer_pid: [type: {:or, [:any, nil]}, default: nil],
      provider_runtime_ready: [type: {:or, [:boolean, nil]}, default: nil],
      runtime_checks: [type: {:or, [:map, nil]}, default: nil],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent],
      shell_session_server_mod: [type: :atom, default: Jido.Shell.ShellSessionServer]
    ]

  alias Jido.Harness.Exec
  alias Jido.Harness.Exec.ProviderRuntime
  alias Jido.Lib.Github.Actions.IssueTriage.Helpers

  @max_body_chars 2_000
  @signal_source "/github/issue_triage/coding_agent"
  @heartbeat_interval_ms 5_000
  @max_raw_line_chars 600

  @impl true
  def run(params, _context) do
    provider = params[:provider] || :claude
    prompt = build_prompt(params)
    prompt_file = "/tmp/jido_triage_prompt_#{params[:run_id] || "run"}.txt"
    timeout = params[:timeout] || 300_000
    observer_pid = params[:observer_pid]

    emit_probe_signal(observer_pid, "started", %{
      run_id: params[:run_id],
      issue_number: params[:issue_number],
      session_id: params[:session_id],
      provider: provider,
      repo_dir: params[:repo_dir]
    })

    with :ok <- ensure_runtime_ready(params),
         :ok <- write_prompt_file(params, prompt_file, prompt),
         {:ok, command} <- ProviderRuntime.build_command(provider, :triage, prompt_file),
         {:ok, result} <-
           Exec.run_stream(
             provider,
             params.session_id,
             params.repo_dir,
             command: command,
             shell_agent_mod: params[:shell_agent_mod] || Jido.Shell.Agent,
             shell_session_server_mod:
               params[:shell_session_server_mod] || Jido.Shell.ShellSessionServer,
             timeout: timeout,
             heartbeat_interval_ms: @heartbeat_interval_ms,
             on_mode: fn mode ->
               emit_probe_signal(observer_pid, "mode", %{
                 provider: provider,
                 mode: mode,
                 session_id: params.session_id
               })
             end,
             on_event: fn event ->
               emit_probe_signal(observer_pid, "event", %{
                 run_id: params[:run_id],
                 issue_number: params[:issue_number],
                 provider: provider,
                 session_id: params[:session_id],
                 event_type: map_get(event, :type),
                 event: event
               })
             end,
             on_raw_line: fn raw_line ->
               emit_probe_signal(observer_pid, "raw_line", %{
                 run_id: params[:run_id],
                 issue_number: params[:issue_number],
                 provider: provider,
                 session_id: params[:session_id],
                 line: sanitize_raw_line(raw_line)
               })
             end,
             on_heartbeat: fn idle_ms ->
               emit_probe_signal(observer_pid, "heartbeat", %{
                 run_id: params[:run_id],
                 issue_number: params[:issue_number],
                 provider: provider,
                 session_id: params[:session_id],
                 idle_ms: idle_ms
               })
             end
           ) do
      agent_status = if result.success?, do: :ok, else: :failed

      agent_error =
        if result.success?, do: nil, else: "provider stream did not emit success marker"

      investigation = result.result_text

      emit_probe_signal(observer_pid, "completed", %{
        run_id: params[:run_id],
        issue_number: params[:issue_number],
        session_id: params[:session_id],
        provider: provider,
        success: result.success?,
        event_count: result.event_count,
        summary_bytes: byte_size(result.result_text || "")
      })

      {:ok,
       Map.merge(Helpers.pass_through(params), %{
         provider: provider,
         investigation: investigation,
         investigation_status: agent_status,
         investigation_error: agent_error,
         agent_status: agent_status,
         agent_summary: investigation,
         agent_error: agent_error
       })}
    else
      {:error, reason} ->
        emit_probe_signal(observer_pid, "failed", %{
          run_id: params[:run_id],
          issue_number: params[:issue_number],
          session_id: params[:session_id],
          provider: provider,
          error: inspect(reason)
        })

        {:ok,
         Map.merge(Helpers.pass_through(params), %{
           provider: provider,
           investigation: nil,
           investigation_status: :failed,
           investigation_error: inspect(reason),
           agent_status: :failed,
           agent_summary: nil,
           agent_error: inspect(reason)
         })}
    end
  end

  defp write_prompt_file(params, prompt_file, prompt) do
    escaped = Helpers.escape_path(prompt_file)
    command = "cat > #{escaped} << 'JIDO_TRIAGE_PROMPT_EOF'\n#{prompt}\nJIDO_TRIAGE_PROMPT_EOF"

    case Helpers.run_in_dir(
           params[:shell_agent_mod] || Jido.Shell.Agent,
           params.session_id,
           params.repo_dir,
           command,
           timeout: 10_000
         ) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:prompt_write_failed, reason}}
    end
  end

  defp ensure_runtime_ready(params) do
    ready? = map_get(params, :provider_runtime_ready, false)
    runtime_checks = map_get(params, :runtime_checks)

    if ready? == true or is_map(runtime_checks) do
      :ok
    else
      {:error, :provider_runtime_not_ready}
    end
  end

  defp emit_probe_signal(pid, suffix, data)
       when is_pid(pid) and is_binary(suffix) and is_map(data) do
    signal =
      Jido.Signal.new!(
        "jido.lib.github.issue_triage.coding_agent.#{suffix}",
        data,
        source: @signal_source
      )

    send(pid, {:jido_lib_signal, signal})
    :ok
  rescue
    _ -> :ok
  end

  defp emit_probe_signal(_pid, _suffix, _data), do: :ok

  defp sanitize_raw_line(raw_line) when is_binary(raw_line) do
    raw_line
    |> String.replace(~r/[\r\n\t]/, " ")
    |> String.slice(0, @max_raw_line_chars)
  end

  defp build_prompt(%{prompt: prompt}) when is_binary(prompt) and prompt != "", do: prompt

  defp build_prompt(%{issue_title: title} = params) when is_binary(title) and title != "" do
    labels = params[:issue_labels] || []
    label_str = if labels != [], do: "\nLabels: #{Enum.join(labels, ", ")}", else: ""
    truncated_body = truncate_body(params[:issue_body] || "")

    """
    Investigate this GitHub issue and report your findings.

    **#{title}** (##{params[:issue_number]})
    #{label_str}

    #{truncated_body}

    Explore the codebase, identify the root cause, and suggest a fix.
    Do NOT modify any files. Report format:
    - Issue Summary
    - Investigation (files examined, tests run)
    - Root Cause
    - Suggested Fix
    """
    |> String.trim()
  end

  defp build_prompt(params) do
    "What can you infer about issue ##{params[:issue_number]} in this repository?"
  end

  defp truncate_body(body) when byte_size(body) <= @max_body_chars, do: body

  defp truncate_body(body),
    do: String.slice(body, 0, @max_body_chars) <> "\n\n... [body truncated]"

  defp map_get(map, key) when is_map(map) and is_atom(key) do
    map_get(map, key, nil)
  end

  defp map_get(map, key, default) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end
