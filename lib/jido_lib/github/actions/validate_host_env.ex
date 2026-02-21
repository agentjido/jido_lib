defmodule Jido.Lib.Github.Actions.ValidateHostEnv do
  @moduledoc """
  Validate required host env vars before any sprite workflow work begins.
  """

  use Jido.Action,
    name: "validate_host_env",
    description: "Validate host env contract for GitHub triage",
    compensation: [max_retries: 0],
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

  alias Jido.Lib.Github.Helpers
  alias Jido.Harness.Exec.ProviderRuntime

  @fallback_forward_vars ["GH_TOKEN", "GITHUB_TOKEN"]
  @default_injected_env %{
    "GH_PROMPT_DISABLED" => "1",
    "GIT_TERMINAL_PROMPT" => "0"
  }
  @gh_env_keys ["GH_TOKEN", "GITHUB_TOKEN"]

  @type validation_error :: %{
          code: atom(),
          message: String.t(),
          provider: atom(),
          missing: [String.t()],
          required_any: [String.t()],
          reason: term() | nil
        }

  @impl true
  def run(params, _context) do
    provider = params[:provider] || :claude

    case validate_host_env(provider) do
      :ok ->
        {:ok, Helpers.pass_through(params)}

      {:error, error} ->
        {:error, {:validate_host_env_failed, error}}
    end
  end

  @doc """
  Validate required host env vars for sprite triage and selected provider.
  """
  @spec validate_host_env(atom()) :: :ok | {:error, validation_error()}
  def validate_host_env(provider \\ :claude)

  def validate_host_env(provider) when is_atom(provider) do
    with :ok <-
           require_env(
             "SPRITES_TOKEN",
             error(
               :missing_sprite_token,
               "SPRITES_TOKEN environment variable not set",
               provider,
               missing: ["SPRITES_TOKEN"]
             )
           ),
         :ok <-
           require_any_env(
             @gh_env_keys,
             error(
               :missing_github_token,
               "GH_TOKEN or GITHUB_TOKEN environment variable not set",
               provider,
               required_any: @gh_env_keys
             )
           ),
         {:ok, contract} <- fetch_provider_runtime_contract(provider),
         :ok <- check_required_all(contract.host_env_required_all || [], provider),
         :ok <- check_required_any(contract.host_env_required_any || [], provider) do
      :ok
    end
  end

  def validate_host_env(provider) do
    {:error,
     error(
       :invalid_provider,
       "provider must be an atom",
       :unknown,
       reason: {:invalid_provider, provider}
     )}
  end

  @doc false
  @spec validate_host_env!(atom()) :: :ok | {:error, validation_error()}
  def validate_host_env!(provider \\ :claude), do: validate_host_env(provider)

  defp check_required_all([], _provider), do: :ok

  defp check_required_all(keys, provider) do
    missing =
      keys
      |> Enum.reject(&present?(System.get_env(&1)))

    if missing == [] do
      :ok
    else
      {:error,
       error(
         :missing_provider_env_all,
         "Provider #{inspect(provider)} requires env vars: #{Enum.join(missing, ", ")}",
         provider,
         missing: missing
       )}
    end
  end

  defp check_required_any([], _provider), do: :ok

  defp check_required_any(keys, provider) do
    if Enum.any?(keys, &present?(System.get_env(&1))) do
      :ok
    else
      {:error,
       error(
         :missing_provider_env_any,
         "Provider #{inspect(provider)} requires at least one of: #{Enum.join(keys, ", ")}",
         provider,
         required_any: keys
       )}
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

  def build_sprite_env(_provider) do
    forward_env =
      @fallback_forward_vars
      |> Enum.reduce(%{}, fn key, acc ->
        case System.get_env(key) do
          nil -> acc
          value -> Map.put(acc, key, value)
        end
      end)

    Map.merge(@default_injected_env, forward_env)
  end

  defp require_env(key, error) do
    if present?(System.get_env(key)) do
      :ok
    else
      {:error, error}
    end
  end

  defp require_any_env(keys, error) when is_list(keys) do
    if Enum.any?(keys, &present?(System.get_env(&1))) do
      :ok
    else
      {:error, error}
    end
  end

  defp fetch_provider_runtime_contract(provider) do
    case ProviderRuntime.provider_runtime_contract(provider) do
      {:ok, contract} ->
        {:ok, contract}

      {:error, reason} ->
        {:error,
         error(
           :provider_runtime_contract_unavailable,
           "Provider runtime contract unavailable",
           provider,
           reason: inspect(reason)
         )}
    end
  end

  defp error(code, message, provider, opts)
       when is_atom(code) and is_binary(message) and is_list(opts) do
    %{
      code: code,
      message: message,
      provider: provider,
      missing: Keyword.get(opts, :missing, []),
      required_any: Keyword.get(opts, :required_any, []),
      reason: Keyword.get(opts, :reason)
    }
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false
end
