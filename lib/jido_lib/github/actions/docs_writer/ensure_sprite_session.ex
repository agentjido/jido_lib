defmodule Jido.Lib.Github.Actions.DocsWriter.EnsureSpriteSession do
  @moduledoc """
  Attaches to an existing sprite session by name, or creates it when missing.
  """

  use Jido.Action,
    name: "docs_writer_ensure_sprite_session",
    description: "Attach-or-create sprite session for docs workflow",
    compensation: [max_retries: 0],
    schema: [
      run_id: [type: :string, required: true],
      sprite_name: [type: :string, required: true],
      workspace_root: [type: :string, required: true],
      sprite_config: [type: :map, required: true],
      timeout: [type: :integer, default: 300_000],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent],
      shell_session_mod: [type: :atom, default: Jido.Shell.ShellSession]
    ]

  alias Jido.Harness.Exec
  alias Jido.Lib.Github.Actions.DocsWriter.Helpers, as: DocsHelpers

  @impl true
  def run(params, _context) do
    case attach_or_create(params) do
      {:ok, result} ->
        {:ok,
         DocsHelpers.pass_through(params)
         |> Map.put(:session_id, result.provisioned.session_id)
         |> Map.put(:sprite_name, result.provisioned.sprite_name)
         |> Map.put(:workspace_dir, result.provisioned.workspace_dir)
         |> Map.put(:sprite_origin, result.origin)
         |> Map.put(:sprite_config, result.sprite_config)}

      {:error, reason} ->
        {:error, {:docs_ensure_sprite_session_failed, reason}}
    end
  end

  defp attach_or_create(params) do
    case provision_with_create(params, false) do
      {:ok, provisioned, sprite_config} ->
        {:ok, %{origin: :attached, provisioned: provisioned, sprite_config: sprite_config}}

      {:error, _attach_reason} ->
        with {:ok, provisioned, sprite_config} <- provision_with_create(params, true) do
          {:ok, %{origin: :created, provisioned: provisioned, sprite_config: sprite_config}}
        end
    end
  end

  defp provision_with_create(params, create?) do
    sprite_config = Map.put(params.sprite_config, :create, create?)

    case Exec.provision_workspace("docs-#{params.run_id}",
           sprite_config: sprite_config,
           session_mod: params[:shell_session_mod] || Jido.Shell.ShellSession,
           agent_mod: params[:shell_agent_mod] || Jido.Shell.Agent,
           timeout: params[:timeout] || 300_000,
           workspace_dir: params.workspace_root,
           sprite_name: params.sprite_name
         ) do
      {:ok, provisioned} -> {:ok, provisioned, sprite_config}
      {:error, reason} -> {:error, reason}
    end
  end
end
