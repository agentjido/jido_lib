defmodule Jido.Lib.Github.Actions.Release.PublishHex do
  @moduledoc """
  Publishes package to Hex when publish mode is enabled.
  """

  use Jido.Action,
    name: "release_publish_hex",
    description: "Publish package to Hex",
    compensation: [max_retries: 0],
    schema: [
      repo_dir: [type: :string, required: true],
      publish: [type: :boolean, default: false],
      apply: [type: :boolean, default: false],
      hex_api_key: [type: {:or, [:string, nil]}, default: nil]
    ]

  alias Jido.Lib.Github.Actions.Common.CommandRunner
  alias Jido.Lib.Github.Actions.Common.MutationGuard
  alias Jido.Lib.Github.Actions.Release.Helpers

  @impl true
  def run(params, _context) do
    cond do
      not MutationGuard.mutation_allowed?(params, publish_only: true) ->
        {:ok, Helpers.pass_through(params)}

      blank?(params[:hex_api_key]) ->
        {:error, {:release_publish_hex_failed, :missing_hex_api_key}}

      true ->
        publish_with_api_key(params)
    end
  end

  defp publish_with_api_key(params) do
    cmd = "export HEX_API_KEY=#{params[:hex_api_key]} && mix hex.publish --yes"

    case CommandRunner.run_local(cmd, repo_dir: params.repo_dir, params: params) do
      {:ok, _} -> {:ok, Helpers.pass_through(params)}
      {:error, reason} -> {:error, {:release_publish_hex_failed, reason}}
    end
  end

  defp blank?(value), do: not (is_binary(value) and value != "")
end
