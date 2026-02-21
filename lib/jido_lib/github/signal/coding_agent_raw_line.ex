defmodule Jido.Lib.Github.Signal.CodingAgentRawLine do
  @moduledoc """
  Signal emitted for raw coding-agent output lines.
  """

  use Jido.Signal,
    type: "jido.lib.github.coding_agent.raw_line",
    default_source: "/github/coding_agent",
    schema: [
      run_id: [type: :string, required: false],
      issue_number: [type: :integer, required: false],
      provider: [type: :atom, required: false],
      agent_mode: [type: :atom, required: false],
      session_id: [type: :string, required: false],
      line: [type: :string, required: false]
    ]
end
