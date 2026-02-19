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

      case run_claude_stream(
             agent_mod,
             session_server_mod,
             params.session_id,
             params.repo_dir,
             cmd,
             timeout,
             observer_pid,
             params
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

  defp run_claude_stream(
         agent_mod,
         session_server_mod,
         session_id,
         repo_dir,
         cmd,
         timeout,
         observer_pid,
         params
       ) do
    emit_probe_signal(observer_pid, "mode", %{
      mode: "session_server_stream",
      session_id: session_id
    })

    case run_streaming_via_session_server(
           session_server_mod,
           session_id,
           repo_dir,
           cmd,
           timeout,
           observer_pid,
           params
         ) do
      {:ok, _output, _events} = ok ->
        ok

      {:error, reason} ->
        if fallback_eligible_reason?(reason) do
          Logger.debug(
            "[Claude] Streaming path unavailable (#{inspect(reason)}), falling back to shell_agent_mod.run/3"
          )

          emit_probe_signal(observer_pid, "mode", %{
            mode: "shell_agent_fallback",
            session_id: session_id
          })

          with {:ok, output} <-
                 Helpers.run_in_dir(agent_mod, session_id, repo_dir, cmd, timeout: timeout) do
            events = parse_all_stream_lines(output, observer_pid, params)
            {:ok, output, events}
          end
        else
          {:error, reason}
        end
    end
  end

  defp run_streaming_via_session_server(
         session_server_mod,
         session_id,
         repo_dir,
         cmd,
         timeout,
         observer_pid,
         params
       ) do
    wrapped = "cd #{Helpers.escape_path(repo_dir)} && #{cmd}"

    with :ok <- ensure_session_server_api(session_server_mod),
         {:ok, :subscribed} <- session_server_mod.subscribe(session_id, self()) do
      drain_shell_events(session_id)

      deadline_ms = monotonic_ms() + timeout

      result =
        case session_server_mod.run_command(session_id, wrapped,
               execution_context: %{max_runtime_ms: timeout}
             ) do
          {:ok, :accepted} ->
            stream_result =
              collect_stream_output(
                session_id,
                deadline_ms,
                observer_pid,
                params,
                "",
                [],
                [],
                false,
                monotonic_ms()
              )

            case stream_result do
              {:error, :timeout} = timeout_error ->
                _ = cancel_command(session_server_mod, session_id)
                timeout_error

              other ->
                other
            end

          {:error, reason} ->
            {:error, reason}
        end

      _ = session_server_mod.unsubscribe(session_id, self())
      result
    end
  end

  defp ensure_session_server_api(mod) when is_atom(mod) do
    if function_exported?(mod, :subscribe, 2) and
         function_exported?(mod, :unsubscribe, 2) and
         function_exported?(mod, :run_command, 3) do
      :ok
    else
      {:error, :unsupported_shell_session_server}
    end
  end

  defp fallback_eligible_reason?(:unsupported_shell_session_server), do: true
  defp fallback_eligible_reason?(%Jido.Shell.Error{code: {:session, :not_found}}), do: true
  defp fallback_eligible_reason?(_), do: false

  defp cancel_command(session_server_mod, session_id) do
    if function_exported?(session_server_mod, :cancel, 1) do
      session_server_mod.cancel(session_id)
    else
      {:error, :cancel_unsupported}
    end
  rescue
    _ -> {:error, :cancel_failed}
  end

  defp collect_stream_output(
         session_id,
         deadline_ms,
         observer_pid,
         params,
         line_buffer,
         output_acc,
         event_acc,
         started?,
         last_event_ms
       ) do
    now = monotonic_ms()
    remaining = deadline_ms - now

    if remaining <= 0 do
      {:error, :timeout}
    else
      receive do
        {:jido_shell_session, ^session_id, {:command_started, _line}} ->
          collect_stream_output(
            session_id,
            deadline_ms,
            observer_pid,
            params,
            line_buffer,
            output_acc,
            event_acc,
            true,
            last_event_ms
          )

        {:jido_shell_session, ^session_id, {:output, chunk}} ->
          {next_buffer, parsed_events, parsed_any?} =
            consume_stream_chunk(line_buffer, chunk, observer_pid, params)

          collect_stream_output(
            session_id,
            deadline_ms,
            observer_pid,
            params,
            next_buffer,
            [chunk | output_acc],
            Enum.reverse(parsed_events) ++ event_acc,
            started?,
            if(parsed_any?, do: monotonic_ms(), else: last_event_ms)
          )

        {:jido_shell_session, ^session_id, {:cwd_changed, _}} ->
          collect_stream_output(
            session_id,
            deadline_ms,
            observer_pid,
            params,
            line_buffer,
            output_acc,
            event_acc,
            started?,
            last_event_ms
          )

        {:jido_shell_session, ^session_id, :command_done} ->
          {trailing_events, trailing_any?} = parse_tail_buffer(line_buffer, observer_pid, params)
          output = output_acc |> Enum.reverse() |> Enum.join() |> String.trim()
          events = Enum.reverse(Enum.reverse(trailing_events) ++ event_acc)
          _ = if trailing_any?, do: monotonic_ms(), else: last_event_ms
          {:ok, output, events}

        {:jido_shell_session, ^session_id, {:error, reason}} ->
          {:error, reason}

        {:jido_shell_session, ^session_id, :command_cancelled} ->
          {:error, :cancelled}

        {:jido_shell_session, ^session_id, {:command_crashed, reason}} ->
          {:error, {:command_crashed, reason}}

        {:jido_shell_session, ^session_id, _event} when not started? ->
          collect_stream_output(
            session_id,
            deadline_ms,
            observer_pid,
            params,
            line_buffer,
            output_acc,
            event_acc,
            started?,
            last_event_ms
          )
      after
        min(@heartbeat_interval_ms, remaining) ->
          idle_ms = monotonic_ms() - last_event_ms

          if idle_ms >= @heartbeat_interval_ms do
            emit_probe_signal(observer_pid, "heartbeat", %{
              run_id: params[:run_id],
              issue_number: params[:issue_number],
              session_id: session_id,
              idle_ms: idle_ms
            })
          end

          collect_stream_output(
            session_id,
            deadline_ms,
            observer_pid,
            params,
            line_buffer,
            output_acc,
            event_acc,
            started?,
            last_event_ms
          )
      end
    end
  end

  defp consume_stream_chunk(buffer, chunk, observer_pid, params) do
    {next_buffer, lines} = split_complete_lines(buffer <> chunk)

    {events, parsed_any?} =
      Enum.reduce(lines, {[], false}, fn line, {acc, any?} ->
        case parse_stream_line(line) do
          {:event, event} ->
            emit_stream_event_signal(observer_pid, event, params)
            {[event | acc], true}

          {:raw, raw_line} ->
            emit_raw_line_signal(observer_pid, raw_line, params)
            {acc, any?}

          :empty ->
            {acc, any?}
        end
      end)

    {next_buffer, Enum.reverse(events), parsed_any?}
  end

  defp parse_tail_buffer("", _observer_pid, _params), do: {[], false}

  defp parse_tail_buffer(buffer, observer_pid, params) do
    case parse_stream_line(buffer) do
      {:event, event} ->
        emit_stream_event_signal(observer_pid, event, params)
        {[event], true}

      {:raw, raw_line} ->
        emit_raw_line_signal(observer_pid, raw_line, params)
        {[], false}

      :empty ->
        {[], false}
    end
  end

  defp split_complete_lines(content) do
    lines = String.split(content, "\n", trim: false)

    case Enum.reverse(lines) do
      [tail | rev_complete] -> {tail, Enum.reverse(rev_complete)}
      [] -> {"", []}
    end
  end

  defp parse_stream_line(line) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        :empty

      true ->
        case Jason.decode(trimmed) do
          {:ok, event} when is_map(event) -> {:event, event}
          _ -> {:raw, trimmed}
        end
    end
  end

  defp parse_all_stream_lines(output, observer_pid, params) do
    output
    |> String.split("\n", trim: true)
    |> Enum.reduce([], fn line, acc ->
      case parse_stream_line(line) do
        {:event, event} ->
          emit_stream_event_signal(observer_pid, event, params)
          [event | acc]

        {:raw, raw_line} ->
          emit_raw_line_signal(observer_pid, raw_line, params)
          acc

        :empty ->
          acc
      end
    end)
    |> Enum.reverse()
  end

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

  defp drain_shell_events(session_id) do
    receive do
      {:jido_shell_session, ^session_id, _event} ->
        drain_shell_events(session_id)
    after
      0 ->
        :ok
    end
  end

  defp monotonic_ms, do: System.monotonic_time(:millisecond)

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
