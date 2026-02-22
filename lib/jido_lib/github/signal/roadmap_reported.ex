defmodule Jido.Lib.Github.Signal.RoadmapReported do
  @moduledoc """
  Signal emitted when roadmap bot emits queue/report output.
  """

  use Jido.Signal,
    type: "jido.lib.github.roadmap.reported",
    default_source: "/github/roadmap_bot",
    schema: [
      run_id: [type: {:or, [:string, nil]}, required: false],
      provider: [type: {:or, [:atom, nil]}, required: false],
      repo: [type: {:or, [:string, nil]}, required: false],
      status: [type: {:or, [:atom, nil]}, required: false],
      items_selected: [type: {:or, [:integer, nil]}, required: false],
      summary: [type: {:or, [:string, nil]}, required: false]
    ]
end
