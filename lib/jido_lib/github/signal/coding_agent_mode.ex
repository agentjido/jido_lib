defmodule Jido.Lib.Github.Signal.CodingAgentMode do
  @moduledoc """
  Signal emitted for coding-agent stream mode transitions.
  """

  use Jido.Signal,
    type: "jido.lib.github.coding_agent.mode",
    default_source: "/github/coding_agent",
    schema: [
      provider: [type: :atom, required: false],
      mode: [type: :string, required: false],
      agent_mode: [type: :atom, required: false],
      session_id: [type: :string, required: false]
    ]
end
