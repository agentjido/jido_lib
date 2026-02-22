defmodule Jido.Lib.Github.Actions.Release.ValidateReleaseEnv do
  @moduledoc """
  Validates required environment for release workflows.
  """

  use Jido.Action,
    name: "release_validate_env",
    description: "Validate release runtime requirements",
    compensation: [max_retries: 0],
    schema: [
      repo: [type: :string, required: true],
      run_id: [type: :string, required: true],
      provider: [type: :atom, default: :codex],
      publish: [type: :boolean, default: false],
      dry_run: [type: :boolean, default: true],
      github_token: [type: {:or, [:string, nil]}, default: nil],
      hex_api_key: [type: {:or, [:string, nil]}, default: nil],
      sprites_token: [type: {:or, [:string, nil]}, default: nil]
    ]

  alias Jido.Lib.Github.Actions.Release.Helpers

  @required_tools ["git", "gh", "mix"]

  @impl true
  def run(params, _context) do
    tools_missing = Enum.reject(@required_tools, &(System.find_executable(&1) != nil))

    case tools_missing do
      [] ->
        validate_credentials(params)

      missing ->
        {:error, {:release_validate_env_failed, {:missing_tools, missing}}}
    end
  end

  defp validate_credentials(params) do
    credentials = resolve_credentials(params)

    if publish_credentials_missing?(params[:publish], credentials) do
      {:error, {:release_validate_env_failed, :missing_publish_credentials}}
    else
      {:ok,
       Helpers.pass_through(params)
       |> Map.put(:github_token, credentials.github_token)
       |> Map.put(:hex_api_key, credentials.hex_api_key)
       |> Map.put(:sprites_token, credentials.sprites_token)
       |> Map.put(:warnings, warning_list(credentials))}
    end
  end

  defp resolve_credentials(params) do
    %{
      github_token:
        params[:github_token] || System.get_env("GH_TOKEN") || System.get_env("GITHUB_TOKEN"),
      hex_api_key: params[:hex_api_key] || System.get_env("HEX_API_KEY"),
      sprites_token: params[:sprites_token] || System.get_env("SPRITES_TOKEN")
    }
  end

  defp publish_credentials_missing?(true, credentials) do
    blank?(credentials.github_token) or blank?(credentials.hex_api_key) or
      blank?(credentials.sprites_token)
  end

  defp publish_credentials_missing?(_, _credentials), do: false

  defp warning_list(credentials) do
    []
    |> maybe_add_warning(:missing_github_token, blank?(credentials.github_token))
    |> maybe_add_warning(:missing_hex_api_key, blank?(credentials.hex_api_key))
    |> maybe_add_warning(:missing_sprites_token, blank?(credentials.sprites_token))
  end

  defp blank?(value), do: not (is_binary(value) and value != "")

  defp maybe_add_warning(warnings, _warning, false), do: warnings
  defp maybe_add_warning(warnings, warning, true), do: [warning | warnings]
end
