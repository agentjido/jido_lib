defmodule Jido.Lib.Github.Actions.Release.ProvisionSprite do
  @moduledoc """
  Reuses quality provisioning logic for release workflows.
  """

  use Jido.Action,
    name: "release_provision_sprite",
    description: "Provision release workspace",
    compensation: [max_retries: 0],
    schema: [
      run_id: [type: :string, required: true],
      repo: [type: :string, required: true],
      timeout: [type: :integer, default: 900_000],
      sprite_config: [type: {:or, [:map, nil]}, default: nil],
      sprites_token: [type: {:or, [:string, nil]}, default: nil],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent],
      shell_session_mod: [type: :atom, default: Jido.Shell.ShellSession]
    ]

  alias Jido.Lib.Github.Actions.Quality.ProvisionSprite, as: QualityProvision

  @impl true
  def run(params, context) do
    target_info = %{
      kind: :github,
      path: Path.join(System.tmp_dir!(), "jido-release-#{params.run_id}")
    }

    sprite_config =
      params[:sprite_config] ||
        case params[:sprites_token] do
          token when is_binary(token) and token != "" -> %{token: token}
          _ -> %{}
        end

    quality_params =
      params
      |> Map.put(:target_info, target_info)
      |> Map.put(:sprite_config, sprite_config)

    QualityProvision.run(quality_params, context)
  end
end
