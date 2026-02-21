defmodule Jido.Lib.Github.Signal.CodingAgentHeartbeat do
  @moduledoc """
  Signal emitted for coding-agent heartbeat intervals.
  """

  use Jido.Signal,
    type: "jido.lib.github.coding_agent.heartbeat",
    default_source: "/github/coding_agent",
    schema: [
      run_id: [type: :string, required: false],
      issue_number: [type: :integer, required: false],
      provider: [type: :atom, required: false],
      agent_mode: [type: :atom, required: false],
      session_id: [type: :string, required: false],
      idle_ms: [type: :integer, required: false]
    ]
end
