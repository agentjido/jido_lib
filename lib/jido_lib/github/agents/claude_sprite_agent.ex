defmodule Jido.Lib.Github.Agents.ClaudeSpriteAgent do
  @moduledoc """
  Child agent that executes delegated Claude runnable work for IssueTriageBot.
  """

  use Jido.Agent,
    name: "github_issue_triage_claude_sprite",
    schema: [
      status: [type: :atom, default: :idle]
    ]

  alias Jido.Lib.Github.Actions.IssueTriage.ExecuteDelegatedRunnable

  @doc false
  @spec plugin_specs() :: [Jido.Plugin.Spec.t()]
  def plugin_specs, do: []

  @impl true
  def on_before_cmd(agent, {ExecuteDelegatedRunnable, params}) when is_map(params) do
    {:ok, agent, {ExecuteDelegatedRunnable, params, %{}, delegated_exec_opts(params)}}
  end

  def on_before_cmd(agent, action), do: {:ok, agent, action}

  @doc false
  def signal_routes(_ctx) do
    [
      {"runic.child.execute", ExecuteDelegatedRunnable}
    ]
  end

  defp delegated_exec_opts(params) do
    timeout =
      case delegated_timeout_ms(params) do
        ms when is_integer(ms) and ms > 0 -> ms + 30_000
        _ -> 0
      end

    [timeout: timeout, max_retries: 0]
  end

  defp delegated_timeout_ms(%{runnable: %Runic.Workflow.Runnable{input_fact: %{value: value}}})
       when is_map(value) do
    case Map.get(value, :timeout) || Map.get(value, "timeout") do
      ms when is_integer(ms) and ms > 0 -> ms
      _ -> nil
    end
  end

  defp delegated_timeout_ms(_), do: nil
end
