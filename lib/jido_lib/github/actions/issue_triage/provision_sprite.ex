defmodule Jido.Lib.Github.Actions.IssueTriage.ProvisionSprite do
  @moduledoc """
  Provision a Sprite VM session and create a run workspace directory.
  """

  use Jido.Action,
    name: "provision_sprite",
    description: "Provision a Sprite VM for triage execution",
    schema: [
      run_id: [type: :string, required: true],
      owner: [type: :string, required: true],
      repo: [type: :string, required: true],
      issue_number: [type: :integer, required: true],
      setup_commands: [type: {:list, :string}, default: []],
      keep_workspace: [type: :boolean, default: false],
      keep_sprite: [type: :boolean, default: false],
      issue_url: [type: {:or, [:string, nil]}, default: nil],
      timeout: [type: :integer, default: 300_000],
      prompt: [type: {:or, [:string, nil]}, default: nil],
      sprite_config: [type: :map, required: true],
      sprites_mod: [type: :atom, default: Sprites],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent],
      shell_session_mod: [type: :atom, default: Jido.Shell.ShellSession]
    ]

  alias Jido.Lib.Github.Actions.IssueTriage.Helpers

  @impl true
  def run(params, _context) do
    sprite_config = params.sprite_config
    workspace_base = sprite_opt(sprite_config, :workspace_base, "/work")
    workspace_dir = "#{workspace_base}/jido-triage-#{params.run_id}"
    sprite_name = sprite_opt(sprite_config, :sprite_name, "jido-triage-#{params.run_id}")

    session_mod = params[:shell_session_mod] || Jido.Shell.ShellSession
    agent_mod = params[:shell_agent_mod] || Jido.Shell.Agent

    with {:ok, provisioned} <-
           Jido.Shell.SpriteLifecycle.provision("triage-#{params.run_id}", sprite_config,
             session_mod: session_mod,
             agent_mod: agent_mod,
             timeout: params[:timeout] || 30_000,
             workspace_dir: workspace_dir,
             sprite_name: sprite_name
           ) do
      passthrough = Helpers.pass_through(params)

      {:ok,
       Map.merge(passthrough, %{
         session_id: provisioned.session_id,
         sprite_name: provisioned.sprite_name,
         workspace_dir: provisioned.workspace_dir,
         timeout: params[:timeout] || 300_000,
         shell_agent_mod: agent_mod,
         shell_session_mod: session_mod,
         sprite_config: sprite_config
       })}
    else
      {:error, reason} ->
        {:error, {:provision_sprite_failed, reason}}
    end
  end

  defp sprite_opt(config, key, default) when is_map(config) do
    Map.get(config, key, Map.get(config, Atom.to_string(key), default))
  end
end
