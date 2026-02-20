defmodule Jido.Lib.Github.Actions.PrepareProviderRuntime do
  @moduledoc """
  Bootstrap provider runtime in Sprite (install/auth setup).
  """

  use Jido.Action,
    name: "prepare_provider_runtime",
    description: "Bootstrap provider runtime prerequisites",
    compensation: [max_retries: 1],
    schema: [
      provider: [type: :atom, default: :claude],
      session_id: [type: :string, required: true],
      repo_dir: [type: {:or, [:string, nil]}, default: nil],
      timeout: [type: :integer, default: 300_000],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent]
    ]

  alias Jido.Harness.Exec
  alias Jido.Lib.Github.Helpers

  @impl true
  def run(params, _context) do
    provider = params[:provider] || :claude
    agent_mod = params[:shell_agent_mod] || Jido.Shell.Agent
    timeout = params[:timeout] || 60_000
    cwd = params[:repo_dir]

    case Exec.bootstrap_provider_runtime(
           provider,
           params.session_id,
           shell_agent_mod: agent_mod,
           timeout: timeout,
           cwd: cwd
         ) do
      {:ok, bootstrap} ->
        {:ok,
         Map.merge(Helpers.pass_through(params), %{
           provider_bootstrap: bootstrap,
           provider_runtime_ready: true
         })}

      {:error, reason} ->
        {:error, {:prepare_provider_runtime_failed, reason}}
    end
  end
end
