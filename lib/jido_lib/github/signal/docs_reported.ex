defmodule Jido.Lib.Github.Signal.DocsReported do
  @moduledoc """
  Signal emitted when documentation writer finalizes or publishes a guide.
  """

  use Jido.Signal,
    type: "jido.lib.github.docs.reported",
    default_source: "/github/documentation_writer_bot",
    schema: [
      run_id: [type: {:or, [:string, nil]}, required: false],
      writer_provider: [type: {:or, [:atom, nil]}, required: false],
      critic_provider: [type: {:or, [:atom, nil]}, required: false],
      output_repo: [type: {:or, [:string, nil]}, required: false],
      output_path: [type: {:or, [:string, nil]}, required: false],
      status: [type: {:or, [:atom, nil]}, required: false],
      decision: [type: {:or, [:atom, nil]}, required: false],
      published: [type: {:or, [:boolean, nil]}, required: false],
      pr_url: [type: {:or, [:string, nil]}, required: false],
      summary: [type: {:or, [:string, nil]}, required: false]
    ]
end
