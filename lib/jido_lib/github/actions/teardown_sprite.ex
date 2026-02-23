defmodule Jido.Lib.Github.Actions.TeardownSprite do
  @moduledoc """
  Tear down a Sprite session after triage completion.
  """

  use Jido.Action,
    name: "teardown_sprite",
    description: "Stop Sprite session and complete triage run",
    compensation: [max_retries: 0],
    schema: [
      run_id: [type: :string, required: true],
      provider: [type: :atom, default: :claude],
      single_pass: [type: :boolean, default: false],
      session_id: [type: :string, required: true],
      workspace_dir: [type: :string, required: true],
      keep_sprite: [type: :boolean, default: false],
      sprite_name: [type: {:or, [:string, nil]}, default: nil],
      sprite_config: [type: {:or, [:map, nil]}, default: nil],
      investigation: [type: {:or, [:string, nil]}, default: nil],
      investigation_status: [type: {:or, [:atom, nil]}, default: nil],
      investigation_error: [type: {:or, [:string, nil]}, default: nil],
      comment_posted: [type: {:or, [:boolean, nil]}, default: nil],
      comment_url: [type: {:or, [:string, nil]}, default: nil],
      comment_error: [type: {:or, [:string, nil]}, default: nil],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent],
      sprites_mod: [type: :atom, default: Sprites]
    ]

  alias Jido.Harness.Exec
  alias Jido.Lib.Github.Helpers

  @impl true
  def run(params, _context) do
    result =
      Helpers.pass_through(params)
      |> Map.merge(%{
        run_id: params.run_id,
        status: :completed
      })

    if params[:keep_sprite] do
      {:ok,
       Map.merge(result, %{
         message: "Sprite preserved: #{params[:sprite_name] || "unknown"}",
         session_id: params.session_id,
         teardown_verified: nil,
         teardown_attempts: nil,
         warnings: params[:warnings]
       })}
    else
      agent_mod = params[:shell_agent_mod] || Jido.Shell.Agent
      sprites_mod = params[:sprites_mod] || Sprites

      teardown =
        Exec.teardown_workspace(
          params.session_id,
          sprite_name: params[:sprite_name],
          stop_mod: agent_mod,
          sprite_config: params[:sprite_config],
          sprites_mod: sprites_mod
        )

      message =
        if teardown.teardown_verified do
          "Sprite destroyed (verified)"
        else
          "Sprite teardown not verified after retries"
        end

      warnings =
        [params[:warnings], teardown.warnings]
        |> List.flatten()
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> case do
          [] -> nil
          list -> list
        end

      {:ok,
       Map.merge(result, %{
         message: message,
         teardown_verified: teardown.teardown_verified,
         teardown_attempts: teardown.teardown_attempts,
         warnings: warnings
       })}
    end
  end
end
