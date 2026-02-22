defmodule Jido.Lib.Github.Actions.Release.TeardownWorkspace do
  @moduledoc """
  Reuses quality teardown behavior for release workflows.
  """

  use Jido.Action,
    name: "release_teardown_workspace",
    description: "Teardown release workspace",
    compensation: [max_retries: 0],
    schema: [
      session_id: [type: {:or, [:string, nil]}, default: nil],
      sprite_name: [type: {:or, [:string, nil]}, default: nil],
      sprite_config: [type: {:or, [:map, nil]}, default: nil],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent],
      run_id: [type: :string, required: true]
    ]

  alias Jido.Lib.Github.Actions.Quality.TeardownWorkspace, as: QualityTeardown

  @impl true
  def run(params, context), do: QualityTeardown.run(params, context)
end
