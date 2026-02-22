defmodule Jido.Lib.Github.Actions.Quality.ValidateHostEnv do
  @moduledoc """
  Validates base host runtime requirements for quality bot runs.
  """

  use Jido.Action,
    name: "quality_validate_host_env",
    description: "Validate host env for quality bot",
    compensation: [max_retries: 0],
    schema: [
      target: [type: :string, required: true],
      run_id: [type: :string, required: true],
      provider: [type: :atom, default: :codex],
      github_token: [type: {:or, [:string, nil]}, default: nil],
      mode: [type: :atom, default: :report],
      apply: [type: :boolean, default: false],
      timeout: [type: :integer, default: 600_000],
      observer_pid: [type: {:or, [:any, nil]}, default: nil]
    ]

  alias Jido.Lib.Github.Actions.Quality.Helpers

  @impl true
  def run(params, _context) do
    provider = params[:provider] || :codex

    if provider in [:claude, :amp, :codex, :gemini] do
      {:ok,
       Helpers.pass_through(params)
       |> Map.put(
         :github_token,
         params[:github_token] || System.get_env("GH_TOKEN") || System.get_env("GITHUB_TOKEN")
       )}
    else
      {:error, {:quality_validate_host_env_failed, {:invalid_provider, provider}}}
    end
  end
end
