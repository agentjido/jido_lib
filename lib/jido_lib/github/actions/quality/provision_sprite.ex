defmodule Jido.Lib.Github.Actions.Quality.ProvisionSprite do
  @moduledoc """
  Optionally provisions a sprite session for quality bot runs.

  Defaults to local execution when sprite config/token is absent.
  """

  use Jido.Action,
    name: "quality_provision_sprite",
    description: "Provision sprite workspace for quality bot",
    compensation: [max_retries: 0],
    schema: [
      run_id: [type: :string, required: true],
      target_info: [type: :map, required: true],
      timeout: [type: :integer, default: 300_000],
      sprite_config: [type: {:or, [:map, nil]}, default: nil],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent],
      shell_session_mod: [type: :atom, default: Jido.Shell.ShellSession]
    ]

  alias Jido.Harness.Exec
  alias Jido.Lib.Github.Actions.Quality.Helpers

  @impl true
  def run(params, _context) do
    sprite_config = params[:sprite_config] || %{}
    token = sprite_token(sprite_config)

    case token do
      token when is_binary(token) and token != "" ->
        provision_sprite_workspace(params, sprite_config, token)

      _ ->
        {:ok,
         Helpers.pass_through(params)
         |> Map.put(:session_id, nil)
         |> Map.put(:sprite_name, nil)
         |> Map.put(:workspace_dir, Map.get(params.target_info, :path, System.tmp_dir!()))
         |> Map.put(:sprite_config, sprite_config)}
    end
  end

  defp provision_sprite_workspace(params, sprite_config, token) do
    workspace_id = "quality-#{params.run_id}"
    workspace_dir = "#{Map.get(params.target_info, :path, System.tmp_dir!())}/.jido-quality"

    case Exec.provision_workspace(workspace_id,
           sprite_config: Map.put(sprite_config, :token, token),
           workspace_dir: workspace_dir,
           shell_agent_mod: params[:shell_agent_mod] || Jido.Shell.Agent,
           session_mod: params[:shell_session_mod] || Jido.Shell.ShellSession,
           timeout: params[:timeout] || 300_000,
           sprite_name: "jido-quality-#{params.run_id}"
         ) do
      {:ok, provisioned} ->
        {:ok,
         Helpers.pass_through(params)
         |> Map.put(:session_id, provisioned.session_id)
         |> Map.put(:sprite_name, provisioned.sprite_name)
         |> Map.put(:workspace_dir, provisioned.workspace_dir)
         |> Map.put(:sprite_config, Map.put(sprite_config, :token, token))}

      {:error, reason} ->
        {:error, {:quality_provision_sprite_failed, reason}}
    end
  end

  defp sprite_token(sprite_config) do
    Map.get(sprite_config, :token) || Map.get(sprite_config, "token") ||
      System.get_env("SPRITES_TOKEN")
  end
end
