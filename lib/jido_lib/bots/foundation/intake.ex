defmodule Jido.Lib.Bots.Foundation.Intake do
  @moduledoc """
  Shared intake normalization helpers for GitHub bot entrypoints.
  """

  alias Jido.Lib.Github.Actions.ValidateHostEnv
  alias Jido.Lib.Github.Helpers

  @spec normalize_run_id(term()) :: String.t()
  def normalize_run_id(run_id) when is_binary(run_id) do
    if String.trim(run_id) == "", do: generate_run_id(), else: run_id
  end

  def normalize_run_id(_), do: generate_run_id()

  @spec normalize_provider!(term(), atom()) :: atom()
  def normalize_provider!(provider, default \\ :codex) when is_atom(default) do
    Helpers.provider_normalize!(provider || default)
  end

  @spec normalize_provider(term(), atom()) :: atom()
  def normalize_provider(provider, fallback \\ :codex) when is_atom(fallback) do
    normalize_provider!(provider, fallback)
  rescue
    _ -> fallback
  end

  @spec normalize_commands(term()) :: [String.t()]
  def normalize_commands(nil), do: []

  def normalize_commands(value) when is_binary(value) do
    case String.trim(value) do
      "" -> []
      command -> [command]
    end
  end

  def normalize_commands(values) when is_list(values) do
    values
    |> Enum.flat_map(&normalize_commands/1)
  end

  def normalize_commands(_), do: []

  @spec build_sprite_config(atom() | [atom()], map() | nil) :: map()
  def build_sprite_config(providers, config \\ nil) do
    default_env = build_default_sprite_env(providers)

    case config do
      %{} = map when map_size(map) > 0 ->
        merge_sprite_config_defaults(map, default_env)

      _ ->
        %{
          token: System.get_env("SPRITES_TOKEN"),
          create: true,
          env: default_env
        }
    end
  end

  defp generate_run_id do
    :crypto.strong_rand_bytes(6)
    |> Base.encode16(case: :lower)
  end

  defp build_default_sprite_env(providers) do
    providers
    |> List.wrap()
    |> Enum.map(&normalize_provider!(&1, :claude))
    |> Enum.uniq()
    |> Enum.reduce(%{}, fn provider, env ->
      Map.merge(env, ValidateHostEnv.build_sprite_env(provider))
    end)
  end

  defp merge_sprite_config_defaults(config, default_env) when is_map(config) do
    existing_env =
      case Helpers.map_get(config, :env, %{}) do
        %{} = env -> env
        _ -> %{}
      end

    token = Helpers.map_get(config, :token, System.get_env("SPRITES_TOKEN"))
    create = Helpers.map_get(config, :create, true)

    config
    |> Map.put(:token, token)
    |> Map.put(:create, create)
    |> Map.put(:env, Map.merge(default_env, existing_env))
  end
end
