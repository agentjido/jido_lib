defmodule Jido.Lib.Github.Plugins.RuntimeContext do
  @moduledoc """
  Runtime context plugin for GitHub bots.

  Keeps runtime metadata explicit and available under plugin state.
  """

  use Jido.Plugin,
    name: "github_runtime_context",
    state_key: :github_runtime_context,
    description: "Runtime context plugin for GitHub bot workflows",
    category: "runtime",
    actions: [],
    signal_patterns: ["runic.feed", "jido.lib.github.*"],
    tags: ["github", "runtime", "context"]

  @impl true
  def mount(_agent, config) when is_map(config) do
    {:ok,
     %{
       request_id: Map.get(config, :request_id),
       run_id: Map.get(config, :run_id),
       provider: Map.get(config, :provider),
       owner: Map.get(config, :owner),
       repo: Map.get(config, :repo),
       issue_number: Map.get(config, :issue_number),
       session_id: Map.get(config, :session_id)
     }}
  end
end
