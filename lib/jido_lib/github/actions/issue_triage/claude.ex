defmodule Jido.Lib.Github.Actions.IssueTriage.Claude do
  @moduledoc """
  Run Claude Code inside the cloned repo for issue investigation.
  """

  use Jido.Action,
    name: "claude",
    description: "Run Claude investigation in repository",
    schema: [
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
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent],
      shell_session_server_mod: [type: :atom, default: Jido.Shell.ShellSessionServer]
    ]

  require Logger

  alias Jido.Lib.Github.Actions.IssueTriage.Helpers

  @max_body_chars 2_000
  @prompt_file "/tmp/jido_claude_prompt.txt"
  @signal_source "/github/issue_triage/claude_probe"
  @heartbeat_interval_ms 5_000
  @max_raw_line_chars 600

  @impl true
  def run(params, _context) do
    agent_mod = params[:shell_agent_mod] || Jido.Shell.Agent
    session_server_mod = params[:shell_session_server_mod] || Jido.Shell.ShellSessionServer
    observer_pid = params[:observer_pid]
    prompt = build_prompt(params)

    write_cmd = "cat > #{@prompt_file} << 'JIDO_PROMPT_EOF'\n#{prompt}\nJIDO_PROMPT_EOF"

    with {:ok, _} <-
           Helpers.run_in_dir(agent_mod, params.session_id, params.repo_dir, write_cmd,
             timeout: 10_000
           ) do
      cmd = claude_stream_json_command()

      emit_probe_signal(observer_pid, "started", %{
        run_id: params[:run_id],
        issue_number: params[:issue_number],
        session_id: params.session_id,
        repo_dir: params.repo_dir
      })

      Logger.info(
        "[Claude] Running claude stream-json mode in #{params.repo_dir} (prompt: #{byte_size(prompt)} bytes)"
      )

      timeout = params[:timeout] || 300_000

      case Jido.Shell.StreamJson.run(
             agent_mod,
             session_server_mod,
             params.session_id,
             params.repo_dir,
             cmd,
             timeout: timeout,
             heartbeat_interval_ms: @heartbeat_interval_ms,
             fallback_eligible?: &fallback_eligible_reason?/1,
             on_mode: fn mode ->
               emit_probe_signal(observer_pid, "mode", %{
                 mode: mode,
                 session_id: params.session_id
               })
             end,
             on_event: fn event ->
               emit_stream_event_signal(observer_pid, event, params)
             end,
             on_raw_line: fn raw_line ->
               emit_raw_line_signal(observer_pid, raw_line, params)
             end,
             on_heartbeat: fn idle_ms ->
               emit_probe_signal(observer_pid, "heartbeat", %{
                 run_id: params[:run_id],
                 issue_number: params[:issue_number],
                 session_id: params.session_id,
                 idle_ms: idle_ms
               })
             end
           ) do
        {:ok, output, events} ->
          investigation = extract_investigation(output, events)

          emit_probe_signal(observer_pid, "completed", %{
            run_id: params[:run_id],
            issue_number: params[:issue_number],
            session_id: params.session_id,
            event_count: length(events),
            investigation_bytes: byte_size(investigation || "")
          })

          {:ok,
           Map.merge(Helpers.pass_through(params), %{
             investigation: investigation,
             investigation_status: :ok,
             investigation_error: nil
           })}

        {:error, reason} ->
          Logger.warning("[Claude] Failed: #{inspect(reason)}")

          emit_probe_signal(observer_pid, "failed", %{
            run_id: params[:run_id],
            issue_number: params[:issue_number],
            session_id: params.session_id,
            error: inspect(reason)
          })

          {:ok,
           Map.merge(Helpers.pass_through(params), %{
             investigation: nil,
             investigation_status: :failed,
             investigation_error: inspect(reason)
           })}
      end
    else
      {:error, reason} ->
        emit_probe_signal(observer_pid, "failed", %{
          run_id: params[:run_id],
          issue_number: params[:issue_number],
          session_id: params.session_id,
          error: "prompt_write_failed=#{inspect(reason)}"
        })

        {:ok,
         Map.merge(Helpers.pass_through(params), %{
           investigation: nil,
           investigation_status: :failed,
           investigation_error: "prompt_write_failed=#{inspect(reason)}"
         })}
    end
  end

  defp claude_stream_json_command do
    "claude -p --output-format stream-json --include-partial-messages --verbose \"$(cat #{@prompt_file})\""
  end

  defp fallback_eligible_reason?(:unsupported_shell_session_server), do: true
  defp fallback_eligible_reason?(%Jido.Shell.Error{code: {:session, :not_found}}), do: true
  defp fallback_eligible_reason?(_), do: false

  defp emit_stream_event_signal(observer_pid, event, params) do
    emit_probe_signal(observer_pid, "event", %{
      run_id: params[:run_id],
      issue_number: params[:issue_number],
      session_id: params[:session_id],
      event_kind: stream_event_kind(event),
      event: event
    })
  end

  defp emit_raw_line_signal(observer_pid, raw_line, params) do
    emit_probe_signal(observer_pid, "raw_line", %{
      run_id: params[:run_id],
      issue_number: params[:issue_number],
      session_id: params[:session_id],
      line: sanitize_raw_line(raw_line)
    })
  end

  defp sanitize_raw_line(raw_line) when is_binary(raw_line) do
    raw_line
    |> String.replace(~r/[\r\n\t]/, " ")
    |> String.slice(0, @max_raw_line_chars)
  end

  defp stream_event_kind(%{"type" => "stream_event", "event" => %{"type" => nested}}),
    do: "stream:#{nested}"

  defp stream_event_kind(%{"type" => type}) when is_binary(type), do: type
  defp stream_event_kind(_), do: "unknown"

  defp emit_probe_signal(pid, suffix, data)
       when is_pid(pid) and is_binary(suffix) and is_map(data) do
    signal =
      Jido.Signal.new!(
        "jido.lib.github.issue_triage.claude_probe.#{suffix}",
        data,
        source: @signal_source
      )

    send(pid, {:jido_lib_signal, signal})
    :ok
  rescue
    _ -> :ok
  end

  defp emit_probe_signal(_pid, _suffix, _data), do: :ok

  defp extract_investigation(raw_output, events) when is_list(events) do
    result_text =
      Enum.find_value(Enum.reverse(events), fn
        %{"type" => "result", "result" => result} when is_binary(result) ->
          String.trim(result)

        _ ->
          nil
      end)

    assistant_text =
      Enum.find_value(Enum.reverse(events), fn
        %{"type" => "assistant", "message" => %{"content" => content}} when is_list(content) ->
          content
          |> Enum.flat_map(fn
            %{"type" => "text", "text" => text} when is_binary(text) -> [text]
            _ -> []
          end)
          |> Enum.join("")
          |> String.trim()
          |> case do
            "" -> nil
            text -> text
          end

        _ ->
          nil
      end)

    delta_text =
      events
      |> Enum.flat_map(fn
        %{
          "type" => "stream_event",
          "event" => %{"type" => "content_block_delta", "delta" => %{"text" => text}}
        }
        when is_binary(text) ->
          [text]

        _ ->
          []
      end)
      |> Enum.join("")
      |> String.trim()
      |> case do
        "" -> nil
        text -> text
      end

    result_text || assistant_text || delta_text || String.trim(raw_output || "")
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

  defp truncate_body(body) do
    String.slice(body, 0, @max_body_chars) <> "\n\n... [body truncated]"
  end
end
