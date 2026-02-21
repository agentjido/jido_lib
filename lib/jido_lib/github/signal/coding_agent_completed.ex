defmodule Jido.Lib.Github.Signal.CodingAgentCompleted do
  @moduledoc """
  Signal emitted when coding-agent execution completes.
  """

  use Jido.Signal,
    type: "jido.lib.github.coding_agent.completed",
    default_source: "/github/coding_agent",
    schema: [
      run_id: [type: :string, required: false],
      issue_number: [type: :integer, required: false],
      session_id: [type: :string, required: false],
      provider: [type: :atom, required: false],
      agent_mode: [type: :atom, required: false],
      success: [type: :boolean, required: false],
      event_count: [type: :integer, required: false],
      summary_bytes: [type: :integer, required: false]
    ]
end
