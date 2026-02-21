defmodule Jido.Lib.Github.Signal.CodingAgentStarted do
  @moduledoc """
  Signal emitted when coding-agent execution starts.
  """

  use Jido.Signal,
    type: "jido.lib.github.coding_agent.started",
    default_source: "/github/coding_agent",
    schema: [
      run_id: [type: :string, required: false],
      issue_number: [type: :integer, required: false],
      session_id: [type: :string, required: false],
      provider: [type: :atom, required: false],
      agent_mode: [type: :atom, required: false],
      repo_dir: [type: :string, required: false]
    ]
end
