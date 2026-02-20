defmodule Jido.Lib.Github.Actions.PrBot.RunCodingAgent do
  @moduledoc """
  Run the selected coding agent in coding mode to implement and commit a fix.
  """

  use Jido.Action,
    name: "run_coding_agent",
    description: "Run provider coding command for PR implementation",
    schema: [
      provider: [type: :atom, default: :claude],
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
      timeout: [type: :integer, default: 600_000],
      run_id: [type: {:or, [:string, nil]}, default: nil],
      observer_pid: [type: {:or, [:any, nil]}, default: nil],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent],
      shell_session_server_mod: [type: :atom, default: Jido.Shell.ShellSessionServer]
    ]

  alias Jido.Harness.Exec
  alias Jido.Harness.Exec.ProviderRuntime
  alias Jido.Lib.Github.Actions.PrBot.Helpers

  @signal_source "/github/pr_bot/coding_agent"
  @heartbeat_interval_ms 5_000
  @max_body_chars 3_000
  @max_raw_line_chars 600

  @impl true
  def run(params, _context) do
    provider = params[:provider] || :claude
    timeout = params[:timeout] || 600_000
    observer_pid = params[:observer_pid]
    prompt = build_prompt(params)
    prompt_file = "/tmp/jido_pr_prompt_#{params[:run_id] || "run"}.txt"

    emit_signal(observer_pid, "started", %{
      run_id: params[:run_id],
      issue_number: params[:issue_number],
      session_id: params[:session_id],
      provider: provider,
      repo_dir: params[:repo_dir]
    })

    with :ok <- write_prompt_file(params, prompt_file, prompt),
         {:ok, command} <- ProviderRuntime.build_command(provider, :coding, prompt_file),
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
                 mode: mode,
                 session_id: params.session_id
               })
             end,
             on_event: fn event ->
               emit_signal(observer_pid, "event", %{
                 run_id: params[:run_id],
                 issue_number: params[:issue_number],
                 provider: provider,
                 session_id: params[:session_id],
                 event_type: map_get(event, :type),
                 event: event
               })
             end,
             on_raw_line: fn raw_line ->
               emit_signal(observer_pid, "raw_line", %{
                 run_id: params[:run_id],
                 issue_number: params[:issue_number],
                 provider: provider,
                 session_id: params[:session_id],
                 line: sanitize_raw_line(raw_line)
               })
             end,
             on_heartbeat: fn idle_ms ->
               emit_signal(observer_pid, "heartbeat", %{
                 run_id: params[:run_id],
                 issue_number: params[:issue_number],
                 provider: provider,
                 session_id: params[:session_id],
                 idle_ms: idle_ms
               })
             end
           ),
         :ok <- ensure_success_marker(result) do
      emit_signal(observer_pid, "completed", %{
        run_id: params[:run_id],
        issue_number: params[:issue_number],
        session_id: params[:session_id],
        provider: provider,
        event_count: result.event_count,
        summary_bytes: byte_size(result.result_text || "")
      })

      output =
        %{
          provider: provider,
          agent_status: :ok,
          agent_summary: result.result_text,
          agent_error: nil
        }
        |> maybe_add_claude_aliases(provider)

      {:ok, Map.merge(Helpers.pass_through(params), output)}
    else
      {:error, reason} ->
        emit_signal(observer_pid, "failed", %{
          run_id: params[:run_id],
          issue_number: params[:issue_number],
          session_id: params[:session_id],
          provider: provider,
          error: inspect(reason)
        })

        {:error, {:run_coding_agent_failed, reason}}
    end
  end

  defp ensure_success_marker(%{success?: true}), do: :ok
  defp ensure_success_marker(_), do: {:error, :missing_success_marker}

  defp write_prompt_file(params, prompt_file, prompt) do
    escaped = Helpers.escape_path(prompt_file)
    command = "cat > #{escaped} << 'JIDO_PR_PROMPT_EOF'\n#{prompt}\nJIDO_PR_PROMPT_EOF"

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

  defp maybe_add_claude_aliases(attrs, :claude) do
    attrs
    |> Map.put(:claude_status, attrs.agent_status)
    |> Map.put(:claude_summary, attrs.agent_summary)
  end

  defp maybe_add_claude_aliases(attrs, _provider), do: attrs

  defp build_prompt(params) do
    labels = params[:issue_labels] || []
    label_text = if labels == [], do: "none", else: Enum.join(labels, ", ")
    check_commands = params[:check_commands] || []

    checks_text =
      if check_commands == [], do: "(none provided)", else: Enum.join(check_commands, "\n- ")

    issue_body = truncate_body(params[:issue_body] || "")
    issue_title = params[:issue_title] || "Issue ##{params[:issue_number]}"
    issue_url = params[:issue_url] || "(unknown)"
    branch_name = params[:branch_name] || "(current)"
    base_branch = params[:base_branch] || "(unknown)"

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

  defp truncate_body(body) when byte_size(body) <= @max_body_chars, do: body
  defp truncate_body(body), do: String.slice(body, 0, @max_body_chars) <> "\n\n... [truncated]"

  defp sanitize_raw_line(raw_line) when is_binary(raw_line) do
    raw_line
    |> String.replace(~r/[\r\n\t]/, " ")
    |> String.slice(0, @max_raw_line_chars)
  end

  defp emit_signal(pid, suffix, data) when is_pid(pid) and is_binary(suffix) and is_map(data) do
    signal =
      Jido.Signal.new!(
        "jido.lib.github.pr_bot.coding_agent.#{suffix}",
        data,
        source: @signal_source
      )

    send(pid, {:jido_lib_signal, signal})
    :ok
  rescue
    _ -> :ok
  end

  defp emit_signal(_pid, _suffix, _data), do: :ok

  defp map_get(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end
end
