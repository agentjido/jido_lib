defmodule Jido.Lib.Github.Plugins.Observability do
  @moduledoc """
  Observability plugin and shared signal-formatting helpers for GitHub bots.
  """

  use Jido.Plugin,
    name: "github_observability",
    state_key: :github_observability,
    description: "Observability plugin for GitHub bot runtime and signal formatting",
    category: "observability",
    actions: [],
    signal_patterns: ["jido.lib.github.*", "runic.*"],
    tags: ["github", "observability", "runtime"]

  alias Jido.Lib.Github.Helpers

  @delta_log_every 200

  @spec print_signal(module(), String.t(), String.t(), map(), non_neg_integer()) ::
          non_neg_integer()
  def print_signal(shell, label, "jido.lib.github.coding_agent.event", data, delta_count) do
    event = Helpers.map_get(data, :event, %{})
    event_type = Helpers.map_get(data, :event_type, Helpers.map_get(event, :type, "unknown"))
    next = delta_count + 1

    if rem(next, @delta_log_every) == 0 do
      shell.info("[#{label}][CodingAgent] events=#{next}")
    end

    if event_type in ["stream_event", "content_block_start"] do
      maybe_log_tool_start(shell, label, event)
    end

    if event_type == "result" do
      shell.info("[#{label}][CodingAgent] result #{result_summary(event)}")
    end

    if event_type == "system" do
      shell.info("[#{label}][CodingAgent] init #{system_summary(event)}")
    end

    next
  end

  def print_signal(shell, label, type, data, delta_count) do
    cond do
      String.starts_with?(type, "jido.lib.github.coding_agent.") ->
        print_coding_agent_signal(shell, label, type, data)
        delta_count

      type == "jido.lib.github.validate_runtime.checked" ->
        shell.info("[#{label}][Runtime] #{runtime_summary(data)}")
        delta_count

      true ->
        delta_count
    end
  end

  defp print_coding_agent_signal(shell, label, "jido.lib.github.coding_agent.started", data) do
    provider = Helpers.map_get(data, :provider, "unknown")
    issue_number = Helpers.map_get(data, :issue_number, "?")
    shell.info("[#{label}][CodingAgent] provider=#{provider} started issue=#{issue_number}")
  end

  defp print_coding_agent_signal(shell, label, "jido.lib.github.coding_agent.mode", data) do
    provider = Helpers.map_get(data, :provider, "unknown")
    mode = Helpers.map_get(data, :mode, "unknown")
    shell.info("[#{label}][CodingAgent] provider=#{provider} mode=#{mode}")
  end

  defp print_coding_agent_signal(shell, label, "jido.lib.github.coding_agent.heartbeat", data) do
    shell.info("[#{label}][CodingAgent] heartbeat idle_ms=#{Helpers.map_get(data, :idle_ms, 0)}")
  end

  defp print_coding_agent_signal(shell, label, "jido.lib.github.coding_agent.completed", data) do
    events = Helpers.map_get(data, :event_count, 0)
    bytes = Helpers.map_get(data, :summary_bytes, 0)
    shell.info("[#{label}][CodingAgent] completed events=#{events} bytes=#{bytes}")
  end

  defp print_coding_agent_signal(shell, label, "jido.lib.github.coding_agent.failed", data) do
    error = Helpers.map_get(data, :error, "unknown")
    shell.info("[#{label}][CodingAgent] failed error=#{error}")
  end

  defp print_coding_agent_signal(shell, label, "jido.lib.github.coding_agent.raw_line", data) do
    line = Helpers.map_get(data, :line, "")
    shell.info("[#{label}][CodingAgent][raw] #{line}")
  end

  defp print_coding_agent_signal(_shell, _label, _type, _data), do: :ok

  defp runtime_summary(data) do
    checks = Helpers.map_get(data, :runtime_checks, %{})
    shared = Helpers.map_get(checks, :shared, checks)
    provider_checks = Helpers.map_get(checks, :provider, %{})

    provider_name =
      Helpers.map_get(checks, :provider_name, Helpers.map_get(data, :provider, "unknown"))

    tools = Helpers.map_get(provider_checks, :tools, %{})
    probes = Helpers.map_get(provider_checks, :probes, [])

    tools_ok =
      case tools do
        map when is_map(map) -> Enum.all?(map, fn {_tool, present?} -> present? == true end)
        _ -> false
      end

    probes_ok =
      case probes do
        list when is_list(list) -> Enum.all?(list, &(Helpers.map_get(&1, :pass?, false) == true))
        _ -> false
      end

    "gh=#{Helpers.map_get(shared, :gh, false)} git=#{Helpers.map_get(shared, :git, false)} token=#{Helpers.map_get(shared, :github_token_visible, false)} auth=#{Helpers.map_get(shared, :gh_auth, false)} provider=#{provider_name} tools_ok=#{tools_ok} probes_ok=#{probes_ok}"
  end

  defp maybe_log_tool_start(shell, label, event) when is_map(event) do
    with %{"event" => %{"content_block" => %{"name" => name}}} <- event do
      shell.info("[#{label}][CodingAgent] tool=#{name}")
    else
      _ -> :ok
    end
  end

  defp maybe_log_tool_start(_shell, _label, _event), do: :ok

  defp result_summary(event) when is_map(event) do
    duration_ms = Helpers.map_get(event, :duration_ms, 0)
    turns = Helpers.map_get(event, :num_turns, 0)
    cost = Helpers.map_get(event, :total_cost_usd, 0)
    status = Helpers.map_get(event, :subtype, "unknown")
    "status=#{status} turns=#{turns} duration_ms=#{duration_ms} cost_usd=#{cost}"
  end

  defp result_summary(_event), do: "status=unknown"

  defp system_summary(event) when is_map(event) do
    model = Helpers.map_get(event, :model, "unknown")
    version = Helpers.map_get(event, :claude_code_version, "unknown")
    "model=#{model} cli=#{version}"
  end

  defp system_summary(_event), do: "model=unknown"
end
