defmodule Jido.Lib.Signal.BotRunStarted do
  @moduledoc """
  Signal emitted when a bot run starts.
  """

  use Jido.Signal,
    type: "jido.lib.github.bot_run.started",
    default_source: "/github/bot_runtime",
    schema: [
      request_id: [type: {:or, [:string, nil]}, required: false],
      run_id: [type: {:or, [:string, nil]}, required: false],
      bot: [type: {:or, [:string, nil]}, required: false],
      provider: [type: {:or, [:atom, nil]}, required: false],
      owner: [type: {:or, [:string, nil]}, required: false],
      repo: [type: {:or, [:string, nil]}, required: false],
      issue_number: [type: {:or, [:integer, nil]}, required: false],
      session_id: [type: {:or, [:string, nil]}, required: false],
      timeout: [type: {:or, [:integer, nil]}, required: false]
    ]
end
