defmodule Jido.Lib.Signal.BotRunFailed do
  @moduledoc """
  Signal emitted when a bot run fails.
  """

  use Jido.Signal,
    type: "jido.lib.github.bot_run.failed",
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
      status: [type: {:or, [:atom, nil]}, required: false],
      error: [type: {:or, [:string, nil]}, required: false]
    ]
end
