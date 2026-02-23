defmodule Jido.Lib.Github.Actions.DocsWriter.PrepareRoleRuntimes do
  @moduledoc """
  Bootstraps writer and critic providers in the current sprite session.
  """

  use Jido.Action,
    name: "docs_writer_prepare_role_runtimes",
    description: "Bootstrap writer/critic runtime prerequisites",
    compensation: [max_retries: 1],
    schema: [
      writer_provider: [type: :atom, required: true],
      critic_provider: [type: :atom, required: true],
      single_pass: [type: :boolean, default: false],
      session_id: [type: :string, required: true],
      repo_dir: [type: {:or, [:string, nil]}, default: nil],
      timeout: [type: :integer, default: 300_000],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent]
    ]

  alias Jido.Harness.Exec
  alias Jido.Lib.Github.Actions.ValidateHostEnv
  alias Jido.Lib.Github.Actions.DocsWriter.Helpers, as: DocsHelpers

  @impl true
  def run(params, _context) do
    providers =
      providers_to_prepare(
        params.writer_provider,
        params.critic_provider,
        params.single_pass == true
      )

    with :ok <- validate_host_env_for_roles(providers),
         {:ok, runtime} <- bootstrap_runtime(providers, params) do
      {:ok,
       DocsHelpers.pass_through(params)
       |> Map.put(:role_runtime, runtime)
       |> Map.put(:role_runtime_ready, Map.new(providers, &{&1, true}))}
    else
      {:error, reason} ->
        {:error, {:docs_prepare_role_runtimes_failed, reason}}
    end
  end

  defp validate_host_env_for_roles(providers) do
    providers
    |> Enum.reduce_while(:ok, fn provider, :ok ->
      case ValidateHostEnv.validate_host_env(provider) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {provider, reason}}}
      end
    end)
  end

  defp bootstrap_runtime(providers, params) do
    timeout = params[:timeout] || 300_000
    shell_agent_mod = params[:shell_agent_mod] || Jido.Shell.Agent

    providers
    |> Enum.reduce_while({:ok, %{}}, fn provider, {:ok, acc} ->
      case Exec.bootstrap_provider_runtime(
             provider,
             params.session_id,
             shell_agent_mod: shell_agent_mod,
             timeout: timeout,
             cwd: params[:repo_dir]
           ) do
        {:ok, runtime} -> {:cont, {:ok, Map.put(acc, provider, runtime)}}
        {:error, reason} -> {:halt, {:error, {provider, reason}}}
      end
    end)
  end

  defp providers_to_prepare(writer_provider, _critic_provider, true) do
    [writer_provider]
    |> Enum.uniq()
  end

  defp providers_to_prepare(writer_provider, critic_provider, false) do
    [writer_provider, critic_provider]
    |> Enum.uniq()
  end
end
