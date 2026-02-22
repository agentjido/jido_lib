defmodule Jido.Lib.Github.Signal.QualityReported do
  @moduledoc """
  Signal emitted when quality bot publishes or finalizes a report.
  """

  use Jido.Signal,
    type: "jido.lib.github.quality.reported",
    default_source: "/github/quality_bot",
    schema: [
      run_id: [type: {:or, [:string, nil]}, required: false],
      provider: [type: {:or, [:atom, nil]}, required: false],
      target: [type: {:or, [:string, nil]}, required: false],
      status: [type: {:or, [:atom, nil]}, required: false],
      findings_count: [type: {:or, [:integer, nil]}, required: false],
      summary: [type: {:or, [:string, nil]}, required: false]
    ]
end
