defmodule Jido.Lib.Github.Actions.IssueTriage.ValidateHostEnv do
  @moduledoc """
  Validate required host env vars before any sprite workflow work begins.
  """

  use Jido.Action,
    name: "validate_host_env",
    description: "Validate host env contract for GitHub triage",
    schema: [
      run_id: [type: :string, required: true],
      owner: [type: :string, required: true],
      repo: [type: :string, required: true],
      issue_number: [type: :integer, required: true],
      issue_url: [type: {:or, [:string, nil]}, default: nil],
      provider: [type: :atom, default: :claude],
      timeout: [type: :integer, default: 300_000],
      keep_workspace: [type: :boolean, default: false],
      keep_sprite: [type: :boolean, default: false],
      setup_commands: [type: {:list, :string}, default: []],
      prompt: [type: {:or, [:string, nil]}, default: nil],
      observer_pid: [type: {:or, [:any, nil]}, default: nil],
      sprite_config: [type: :map, required: true],
      sprites_mod: [type: :atom, default: Sprites],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent],
      shell_session_mod: [type: :atom, default: Jido.Shell.ShellSession]
    ]

  alias Jido.Lib.Github.Actions.IssueTriage.Helpers
  alias Jido.Harness.Exec.ProviderRuntime

  @fallback_forward_vars ["GH_TOKEN", "GITHUB_TOKEN"]
  @default_injected_env %{
    "GH_PROMPT_DISABLED" => "1",
    "GIT_TERMINAL_PROMPT" => "0"
  }

  @impl true
  def run(params, _context) do
    provider = params[:provider] || :claude
    validate_host_env!(provider)
    {:ok, Helpers.pass_through(params)}
  end

  @doc """
  Validate required host env vars for sprite triage and selected provider.
  """
  @spec validate_host_env!(atom()) :: :ok | no_return()
  def validate_host_env!(provider \\ :claude)

  def validate_host_env!(provider) when is_atom(provider) do
    require_env!("SPRITES_TOKEN", "SPRITES_TOKEN environment variable not set")

    require_any_env!(
      ["GH_TOKEN", "GITHUB_TOKEN"],
      "GH_TOKEN or GITHUB_TOKEN environment variable not set"
    )

    case ProviderRuntime.provider_runtime_contract(provider) do
      {:ok, contract} ->
        check_required_all(contract.host_env_required_all || [], provider)
        check_required_any(contract.host_env_required_any || [], provider)
        :ok

      {:error, reason} ->
        raise "Provider #{inspect(provider)} runtime contract unavailable: #{inspect(reason)}"
    end
  end

  def validate_host_env!(provider) do
    raise "provider must be an atom, got: #{inspect(provider)}"
  end

  defp check_required_all([], _provider), do: :ok

  defp check_required_all(keys, provider) do
    missing =
      keys
      |> Enum.reject(&present?(System.get_env(&1)))

    if missing == [] do
      :ok
    else
      raise "Provider #{inspect(provider)} requires env vars: #{Enum.join(missing, ", ")}"
    end
  end

  defp check_required_any([], _provider), do: :ok

  defp check_required_any(keys, provider) do
    if Enum.any?(keys, &present?(System.get_env(&1))) do
      :ok
    else
      raise "Provider #{inspect(provider)} requires at least one of: #{Enum.join(keys, ", ")}"
    end
  end

  @doc """
  Build the env map propagated into Sprite sessions for the selected provider.
  """
  @spec build_sprite_env(atom()) :: map()
  def build_sprite_env(provider \\ :claude)

  def build_sprite_env(provider) when is_atom(provider) do
    {forward_vars, injected} =
      case ProviderRuntime.provider_runtime_contract(provider) do
        {:ok, contract} ->
          {
            Enum.uniq(@fallback_forward_vars ++ (contract.sprite_env_forward || [])),
            Map.merge(@default_injected_env, contract.sprite_env_injected || %{})
          }

        {:error, _} ->
          {@fallback_forward_vars, @default_injected_env}
      end

    forward_env =
      forward_vars
      |> Enum.reduce(%{}, fn key, acc ->
        case System.get_env(key) do
          nil -> acc
          value -> Map.put(acc, key, value)
        end
      end)

    Map.merge(injected, forward_env)
  end

  def build_sprite_env(provider) do
    raise "provider must be an atom, got: #{inspect(provider)}"
  end

  defp require_env!(key, message) do
    if present?(System.get_env(key)) do
      :ok
    else
      raise message
    end
  end

  defp require_any_env!(keys, message) when is_list(keys) do
    if Enum.any?(keys, &present?(System.get_env(&1))) do
      :ok
    else
      raise message
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false
end
