defmodule Jido.Lib.Github.Signal.ReleaseReported do
  @moduledoc """
  Signal emitted when release bot produces a release summary.
  """

  use Jido.Signal,
    type: "jido.lib.github.release.reported",
    default_source: "/github/release_bot",
    schema: [
      run_id: [type: {:or, [:string, nil]}, required: false],
      provider: [type: {:or, [:atom, nil]}, required: false],
      repo: [type: {:or, [:string, nil]}, required: false],
      status: [type: {:or, [:atom, nil]}, required: false],
      version: [type: {:or, [:string, nil]}, required: false],
      summary: [type: {:or, [:string, nil]}, required: false]
    ]
end
