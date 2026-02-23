defmodule Jido.Lib.Bots.Foundation.RoleRunner do
  @moduledoc """
  Shared writer/critic command runner backed by `Jido.Harness.Exec.run_stream/4`.
  """

  alias Jido.Harness.Exec
  alias Jido.Harness.Exec.ProviderRuntime
  alias Jido.Lib.Github.Helpers

  @default_timeout_ms 300_000
  @prompt_write_timeout_ms 30_000
  @prompt_write_backoff_ms 250
  @prompt_write_attempts div(@prompt_write_timeout_ms, @prompt_write_backoff_ms)

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

      with :ok <-
             write_prompt(
               shell_agent_mod,
               shell_session_server_mod,
               session_id,
               repo_dir,
               prompt_file,
               prompt
             ),
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
        summary = extract_summary(result)

        {:ok,
         %{
           role: role,
           provider: provider,
           prompt_file: prompt_file,
           command: command,
           success?: result.success?,
           event_count: result.event_count,
           summary: summary,
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

  defp write_prompt(
         shell_agent_mod,
         shell_session_server_mod,
         session_id,
         repo_dir,
         prompt_file,
         prompt
       )
       when is_atom(shell_agent_mod) and is_atom(shell_session_server_mod) and
              is_binary(session_id) and is_binary(repo_dir) and is_binary(prompt_file) and
              is_binary(prompt) do
    with :ok <- wait_for_session_idle(shell_session_server_mod, session_id),
         :ok <-
           write_prompt_via_shell(
             shell_agent_mod,
             session_id,
             repo_dir,
             prompt_file,
             prompt,
             @prompt_write_attempts
           ) do
      :ok
    else
      {:error, reason} ->
        {:error, {:prompt_write_failed, reason}}
    end
  end

  defp write_prompt_via_shell(
         shell_agent_mod,
         session_id,
         repo_dir,
         prompt_file,
         prompt,
         attempts_left
       )
       when is_atom(shell_agent_mod) and is_binary(session_id) and is_binary(repo_dir) and
              is_binary(prompt_file) and is_binary(prompt) and is_integer(attempts_left) and
              attempts_left >= 0 do
    escaped = Helpers.escape_path(prompt_file)
    eof_marker = "JIDO_TRIAGE_CRITIC_PROMPT_EOF"
    command = "cat > #{escaped} << '#{eof_marker}'\n#{prompt}\n#{eof_marker}"

    case Helpers.run_in_dir(shell_agent_mod, session_id, repo_dir, command, timeout: 10_000) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        retry_or_fail_prompt_write(
          reason,
          shell_agent_mod,
          session_id,
          repo_dir,
          prompt_file,
          prompt,
          attempts_left
        )
    end
  end

  defp retry_or_fail_prompt_write(
         reason,
         shell_agent_mod,
         session_id,
         repo_dir,
         prompt_file,
         prompt,
         attempts_left
       )
       when attempts_left > 0 do
    if shell_busy?(reason) do
      Process.sleep(@prompt_write_backoff_ms)

      write_prompt_via_shell(
        shell_agent_mod,
        session_id,
        repo_dir,
        prompt_file,
        prompt,
        attempts_left - 1
      )
    else
      {:error, reason}
    end
  end

  defp retry_or_fail_prompt_write(
         reason,
         _shell_agent_mod,
         _session_id,
         _repo_dir,
         _prompt_file,
         _prompt,
         0
       ) do
    if shell_busy?(reason) do
      {:error, {:shell_busy_timeout, reason}}
    else
      {:error, reason}
    end
  end

  defp wait_for_session_idle(shell_session_server_mod, session_id)
       when is_atom(shell_session_server_mod) and is_binary(session_id) do
    if function_exported?(shell_session_server_mod, :get_state, 1) do
      do_wait_for_session_idle(shell_session_server_mod, session_id, @prompt_write_attempts)
    else
      :ok
    end
  end

  defp do_wait_for_session_idle(_shell_session_server_mod, _session_id, 0) do
    {:error, :shell_not_idle_timeout}
  end

  defp do_wait_for_session_idle(shell_session_server_mod, session_id, attempts_left) do
    case shell_session_server_mod.get_state(session_id) do
      {:ok, state} when is_map(state) ->
        if Map.get(state, :current_command) do
          Process.sleep(@prompt_write_backoff_ms)
          do_wait_for_session_idle(shell_session_server_mod, session_id, attempts_left - 1)
        else
          :ok
        end

      {:ok, _state} ->
        :ok

      {:error, _reason} ->
        :ok
    end
  end

  defp shell_busy?(%Jido.Shell.Error{code: {:shell, :busy}}), do: true
  defp shell_busy?(%{code: {:shell, :busy}}), do: true
  defp shell_busy?(_), do: false

  defp ensure_success_marker(%{success?: true}), do: :ok
  defp ensure_success_marker(_), do: {:error, :missing_success_marker}

  defp extract_summary(%{} = result) do
    events = map_get(result, :events, [])
    result_text = map_get(result, :result_text)
    output = map_get(result, :output)

    extract_summary_from_events(events) ||
      extract_summary_from_json_lines(result_text) ||
      normalize_text(result_text) ||
      extract_summary_from_json_lines(output) ||
      normalize_text(output)
  end

  defp extract_summary(_), do: nil

  defp extract_summary_from_events(events) when is_list(events) do
    events
    |> Enum.reverse()
    |> Enum.find_value(&extract_summary_from_event/1)
  end

  defp extract_summary_from_events(_), do: nil

  defp extract_summary_from_event(event) when is_map(event) do
    type = event_type(event)

    cond do
      type == "result" ->
        normalize_text(map_get(event, :result))

      type == "assistant" ->
        extract_assistant_message(event)

      type in ["item.completed", "item_completed"] ->
        extract_item_completed_text(event)

      type == "output_text_final" ->
        normalize_text(map_get(map_get(event, :payload, %{}), :text))

      true ->
        normalize_text(map_get(event, :output_text))
    end
  end

  defp extract_summary_from_event(_), do: nil

  defp extract_assistant_message(event) when is_map(event) do
    with %{} = message <- map_get(event, :message, %{}),
         content when is_list(content) <- map_get(message, :content, []),
         text when is_binary(text) <- content_text(content),
         text <- normalize_text(text) do
      text
    else
      _ -> nil
    end
  end

  defp extract_assistant_message(_), do: nil

  defp content_text(content) when is_list(content) do
    content
    |> Enum.flat_map(fn
      %{} = part ->
        if map_get(part, :type) == "text" do
          case normalize_text(map_get(part, :text)) do
            nil -> []
            text -> [text]
          end
        else
          []
        end

      _ ->
        []
    end)
    |> Enum.join("")
    |> normalize_text()
  end

  defp content_text(_), do: nil

  defp extract_item_completed_text(event) do
    item = map_get(event, :item, %{})
    item_type = map_get(item, :type)

    if item_type in ["agent_message", :agent_message, "assistant_message", :assistant_message] do
      normalize_text(map_get(item, :text))
    else
      nil
    end
  end

  defp extract_summary_from_json_lines(text) when is_binary(text) do
    text
    |> String.split("\n")
    |> Enum.reduce([], fn line, acc ->
      case Jason.decode(line) do
        {:ok, %{} = event} -> [event | acc]
        _ -> acc
      end
    end)
    |> case do
      [] -> nil
      events -> extract_summary_from_events(Enum.reverse(events))
    end
  end

  defp extract_summary_from_json_lines(_), do: nil

  defp normalize_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end

  defp normalize_text(_), do: nil

  defp event_type(event) when is_map(event) do
    map_get(event, :type)
    |> case do
      type when is_atom(type) -> Atom.to_string(type)
      type when is_binary(type) -> type
      _ -> ""
    end
  end

  defp map_get(map, key, default \\ nil) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

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
