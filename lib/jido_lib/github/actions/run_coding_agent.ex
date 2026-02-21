defmodule Jido.Lib.Github.Actions.RunCodingAgent do
  @moduledoc """
  Run the selected coding agent in triage or coding mode.
  """

  use Jido.Action,
    name: "run_coding_agent",
    description: "Run provider coding/triage command in repository",
    compensation: [max_retries: 0],
    schema: [
      provider: [type: :atom, default: :claude],
      agent_mode: [type: :atom, default: :coding],
      repo_dir: [type: :string, required: true],
      session_id: [type: :string, required: true],
      issue_number: [type: :integer, required: true],
      issue_url: [type: {:or, [:string, nil]}, default: nil],
      issue_title: [type: {:or, [:string, nil]}, default: nil],
      issue_body: [type: {:or, [:string, nil]}, default: nil],
      issue_labels: [type: {:list, :string}, default: []],
      branch_name: [type: {:or, [:string, nil]}, default: nil],
      base_branch: [type: {:or, [:string, nil]}, default: nil],
      check_commands: [type: {:list, :string}, default: []],
      timeout: [type: {:or, [:integer, nil]}, default: nil],
      prompt: [type: {:or, [:string, nil]}, default: nil],
      run_id: [type: {:or, [:string, nil]}, default: nil],
      observer_pid: [type: {:or, [:any, nil]}, default: nil],
      provider_runtime_ready: [type: {:or, [:boolean, nil]}, default: nil],
      runtime_checks: [type: {:or, [:map, nil]}, default: nil],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent],
      shell_session_server_mod: [type: :atom, default: Jido.Shell.ShellSessionServer]
    ]

  alias Jido.Harness.Exec
  alias Jido.Harness.Exec.ProviderRuntime
  alias Jido.Lib.Github.Helpers
  alias Jido.Lib.Github.Observe

  alias Jido.Lib.Github.Signal.{
    CodingAgentCompleted,
    CodingAgentEvent,
    CodingAgentFailed,
    CodingAgentHeartbeat,
    CodingAgentMode,
    CodingAgentRawLine,
    CodingAgentStarted
  }

  @heartbeat_interval_ms 5_000
  @max_raw_line_chars 600
  @triage_max_body_chars 2_000
  @coding_max_body_chars 3_000
  @default_timeout_ms %{triage: 300_000, coding: 600_000}
  @signal_module_by_suffix %{
    "started" => CodingAgentStarted,
    "mode" => CodingAgentMode,
    "event" => CodingAgentEvent,
    "raw_line" => CodingAgentRawLine,
    "heartbeat" => CodingAgentHeartbeat,
    "completed" => CodingAgentCompleted,
    "failed" => CodingAgentFailed
  }

  @impl true
  def run(params, _context) do
    provider = params[:provider] || :claude
    agent_mode = normalize_agent_mode(params[:agent_mode])
    prompt = build_prompt(agent_mode, params)
    prompt_file = prompt_file(agent_mode, params[:run_id])
    timeout = params[:timeout] || @default_timeout_ms[agent_mode]
    observer_pid = params[:observer_pid]

    emit_signal(observer_pid, "started", %{
      run_id: params[:run_id],
      issue_number: params[:issue_number],
      session_id: params[:session_id],
      provider: provider,
      agent_mode: agent_mode,
      repo_dir: params[:repo_dir]
    })

    with :ok <- ensure_runtime_ready(params),
         :ok <- write_prompt_file(params, prompt_file, prompt, agent_mode),
         {:ok, command} <-
           ProviderRuntime.build_command(provider, provider_mode(agent_mode), prompt_file),
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
               emit_signal(observer_pid, "mode", %{
                 provider: provider,
                 mode: normalize_signal_value(mode),
                 agent_mode: agent_mode,
                 session_id: params.session_id
               })
             end,
             on_event: fn event ->
               emit_signal(observer_pid, "event", %{
                 run_id: params[:run_id],
                 issue_number: params[:issue_number],
                 provider: provider,
                 agent_mode: agent_mode,
                 session_id: params[:session_id],
                 event_type: normalize_signal_value(Helpers.map_get(event, :type)),
                 event: event
               })
             end,
             on_raw_line: fn raw_line ->
               emit_signal(observer_pid, "raw_line", %{
                 run_id: params[:run_id],
                 issue_number: params[:issue_number],
                 provider: provider,
                 agent_mode: agent_mode,
                 session_id: params[:session_id],
                 line: sanitize_raw_line(raw_line)
               })
             end,
             on_heartbeat: fn idle_ms ->
               emit_signal(observer_pid, "heartbeat", %{
                 run_id: params[:run_id],
                 issue_number: params[:issue_number],
                 provider: provider,
                 agent_mode: agent_mode,
                 session_id: params[:session_id],
                 idle_ms: idle_ms
               })
             end
           ),
         :ok <- ensure_success_marker(result, agent_mode) do
      emit_signal(observer_pid, "completed", %{
        run_id: params[:run_id],
        issue_number: params[:issue_number],
        session_id: params[:session_id],
        provider: provider,
        agent_mode: agent_mode,
        success: result.success?,
        event_count: result.event_count,
        summary_bytes: byte_size(result.result_text || "")
      })

      emit_summary_telemetry(params, provider, agent_mode, :completed, result, nil)

      {:ok, success_output(params, provider, agent_mode, result)}
    else
      {:error, reason} ->
        emit_signal(observer_pid, "failed", %{
          run_id: params[:run_id],
          issue_number: params[:issue_number],
          session_id: params[:session_id],
          provider: provider,
          agent_mode: agent_mode,
          error: inspect(reason)
        })

        emit_summary_telemetry(params, provider, agent_mode, :failed, nil, reason)

        failure_output(params, provider, agent_mode, reason)
    end
  end

  defp success_output(params, provider, agent_mode, result) do
    agent_status = if result.success?, do: :ok, else: :failed

    agent_error =
      if result.success?, do: nil, else: "provider stream did not emit success marker"

    base =
      Map.merge(Helpers.pass_through(params), %{
        provider: provider,
        agent_mode: agent_mode,
        agent_status: agent_status,
        agent_summary: result.result_text,
        agent_error: agent_error
      })

    if agent_mode == :triage do
      Map.merge(base, %{
        investigation: result.result_text,
        investigation_status: agent_status,
        investigation_error: agent_error
      })
    else
      base
    end
  end

  defp failure_output(params, provider, :triage, reason) do
    {:ok,
     Map.merge(Helpers.pass_through(params), %{
       provider: provider,
       agent_mode: :triage,
       investigation: nil,
       investigation_status: :failed,
       investigation_error: inspect(reason),
       agent_status: :failed,
       agent_summary: nil,
       agent_error: inspect(reason)
     })}
  end

  defp failure_output(_params, _provider, :coding, reason) do
    {:error, {:run_coding_agent_failed, reason}}
  end

  defp ensure_success_marker(%{success?: true}, _mode), do: :ok
  defp ensure_success_marker(_, :triage), do: :ok
  defp ensure_success_marker(_, :coding), do: {:error, :missing_success_marker}

  defp write_prompt_file(params, prompt_file, prompt, agent_mode) do
    escaped = Helpers.escape_path(prompt_file)
    eof_marker = prompt_eof(agent_mode)
    command = "cat > #{escaped} << '#{eof_marker}'\n#{prompt}\n#{eof_marker}"

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
    ready? = Helpers.map_get(params, :provider_runtime_ready, false)
    runtime_checks = Helpers.map_get(params, :runtime_checks)

    if ready? == true or is_map(runtime_checks) do
      :ok
    else
      {:error, :provider_runtime_not_ready}
    end
  end

  defp emit_signal(pid, suffix, data)
       when is_pid(pid) and is_binary(suffix) and is_map(data) do
    with {:ok, module} <- Map.fetch(@signal_module_by_suffix, suffix),
         {:ok, signal} <- module.new(data) do
      send(pid, {:jido_lib_signal, signal})
      :ok
    else
      _ -> :ok
    end
  rescue
    _ -> :ok
  end

  defp emit_signal(_pid, _suffix, _data), do: :ok

  defp sanitize_raw_line(raw_line) when is_binary(raw_line) do
    raw_line
    |> String.replace(~r/[\r\n\t]/, " ")
    |> String.slice(0, @max_raw_line_chars)
  end

  defp normalize_agent_mode(:triage), do: :triage
  defp normalize_agent_mode("triage"), do: :triage
  defp normalize_agent_mode(:coding), do: :coding
  defp normalize_agent_mode("coding"), do: :coding
  defp normalize_agent_mode(_), do: :coding

  defp provider_mode(:triage), do: :triage
  defp provider_mode(:coding), do: :coding

  defp prompt_file(:triage, run_id), do: "/tmp/jido_triage_prompt_#{run_id || "run"}.txt"
  defp prompt_file(:coding, run_id), do: "/tmp/jido_pr_prompt_#{run_id || "run"}.txt"

  defp prompt_eof(:triage), do: "JIDO_TRIAGE_PROMPT_EOF"
  defp prompt_eof(:coding), do: "JIDO_PR_PROMPT_EOF"

  defp build_prompt(_agent_mode, %{prompt: prompt}) when is_binary(prompt) and prompt != "",
    do: prompt

  defp build_prompt(:triage, params), do: triage_prompt(params)
  defp build_prompt(:coding, params), do: coding_prompt(params)

  defp triage_prompt(%{issue_title: title} = params) when is_binary(title) and title != "" do
    labels = params[:issue_labels] || []
    label_str = if labels != [], do: "\nLabels: #{Enum.join(labels, ", ")}", else: ""
    truncated_body = truncate_body(params[:issue_body] || "", :triage)

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

  defp triage_prompt(params) do
    "What can you infer about issue ##{params[:issue_number]} in this repository?"
  end

  defp coding_prompt(params) do
    issue_body = truncate_body(optional_binary(params[:issue_body], ""), :coding)
    issue_title = optional_binary(params[:issue_title], "Issue ##{params[:issue_number]}")
    issue_url = optional_binary(params[:issue_url], "(unknown)")
    branch_name = optional_binary(params[:branch_name], "(current)")
    base_branch = optional_binary(params[:base_branch], "(unknown)")
    label_text = format_labels(params[:issue_labels])
    checks_text = format_check_commands(params[:check_commands])

    """
    You are implementing a fix for a GitHub issue in this repository.

    Issue: #{issue_title}
    Issue Number: ##{params[:issue_number]}
    Issue URL: #{issue_url}
    Labels: #{label_text}
    Target Branch: #{branch_name}
    Base Branch: #{base_branch}

    Issue Body:
    #{issue_body}

    Tasks:
    1. Investigate and implement the fix in this repository.
    2. Update tests/docs if needed.
    3. Run checks (best effort now, hard gate is handled by outer workflow):
       - #{checks_text}
    4. Commit your changes to the current branch.

    Constraints:
    - Do not push the branch.
    - Do not open a pull request.
    - Do not ask for interactive input.
    """
    |> String.trim()
  end

  defp format_labels(labels) do
    labels
    |> normalize_string_list()
    |> case do
      [] -> "none"
      values -> Enum.join(values, ", ")
    end
  end

  defp format_check_commands(commands) do
    commands
    |> normalize_string_list()
    |> case do
      [] -> "(none provided)"
      values -> Enum.join(values, "\n- ")
    end
  end

  defp normalize_string_list(list) when is_list(list) do
    Enum.filter(list, &is_binary/1)
  end

  defp normalize_string_list(_), do: []

  defp optional_binary(value, _fallback) when is_binary(value) and value != "", do: value
  defp optional_binary(_value, fallback), do: fallback

  defp truncate_body(body, :triage) when byte_size(body) <= @triage_max_body_chars, do: body

  defp truncate_body(body, :triage),
    do: String.slice(body, 0, @triage_max_body_chars) <> "\n\n... [body truncated]"

  defp truncate_body(body, :coding) when byte_size(body) <= @coding_max_body_chars, do: body

  defp truncate_body(body, :coding),
    do: String.slice(body, 0, @coding_max_body_chars) <> "\n\n... [truncated]"

  defp emit_summary_telemetry(params, provider, agent_mode, status, result, reason) do
    measurements = %{
      event_count: if(is_map(result), do: result.event_count || 0, else: 0),
      summary_bytes: if(is_map(result), do: byte_size(result.result_text || ""), else: 0),
      system_time: System.system_time()
    }

    metadata = %{
      run_id: params[:run_id],
      provider: provider,
      agent_mode: agent_mode,
      owner: params[:owner],
      repo: params[:repo],
      issue_number: params[:issue_number],
      node: :run_coding_agent,
      attempt: 0,
      session_id: params[:session_id],
      sprite_name: params[:sprite_name],
      status: status,
      error: if(reason, do: inspect(reason), else: nil)
    }

    Observe.emit(Observe.coding_agent(:summary), measurements, metadata)
  rescue
    _ -> :ok
  end

  defp normalize_signal_value(nil), do: nil
  defp normalize_signal_value(value) when is_binary(value), do: value
  defp normalize_signal_value(value), do: to_string(value)
end
