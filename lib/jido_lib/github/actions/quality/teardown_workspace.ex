defmodule Jido.Lib.Github.Actions.Quality.TeardownWorkspace do
  @moduledoc """
  Tears down sprite workspace if session-based provisioning was used.
  """

  use Jido.Action,
    name: "quality_teardown_workspace",
    description: "Teardown quality bot workspace",
    compensation: [max_retries: 0],
    schema: [
      session_id: [type: {:or, [:string, nil]}, default: nil],
      sprite_name: [type: {:or, [:string, nil]}, default: nil],
      sprite_config: [type: {:or, [:map, nil]}, default: nil],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent],
      run_id: [type: :string, required: true]
    ]

  alias Jido.Harness.Exec
  alias Jido.Lib.Github.Actions.Quality.Helpers

  @impl true
  def run(params, _context) do
    teardown =
      case params[:session_id] do
        session_id when is_binary(session_id) and session_id != "" ->
          Exec.teardown_workspace(
            session_id,
            sprite_name: params[:sprite_name],
            stop_mod: params[:shell_agent_mod] || Jido.Shell.Agent,
            sprite_config: params[:sprite_config] || %{},
            sprites_mod: Sprites
          )

        _ ->
          %{teardown_verified: true, teardown_attempts: 0, warnings: []}
      end

    {:ok,
     Helpers.pass_through(params)
     |> Map.put(:teardown_verified, teardown.teardown_verified)
     |> Map.put(:teardown_attempts, teardown.teardown_attempts)
     |> Map.put(:warnings, teardown.warnings)}
  end
end
