defmodule Jido.Lib.Github.Signal.CodingAgentEvent do
  @moduledoc """
  Signal emitted for coding-agent stream events.
  """

  use Jido.Signal,
    type: "jido.lib.github.coding_agent.event",
    default_source: "/github/coding_agent",
    schema: [
      run_id: [type: :string, required: false],
      issue_number: [type: :integer, required: false],
      provider: [type: :atom, required: false],
      agent_mode: [type: :atom, required: false],
      session_id: [type: :string, required: false],
      event_type: [type: :string, required: false],
      event: [type: :map, required: false]
    ]
end
