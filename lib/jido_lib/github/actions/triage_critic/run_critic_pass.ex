defmodule Jido.Lib.Github.Actions.TriageCritic.RunCriticPass do
  @moduledoc """
  Executes critic pass and persists structured critique artifacts.
  """

  use Jido.Action,
    name: "triage_critic_run_critic_pass",
    description: "Run critic role and emit structured critique report",
    compensation: [max_retries: 0],
    schema: [
      iteration: [type: :integer, required: true],
      run_id: [type: :string, required: true],
      session_id: [type: :string, required: true],
      repo_dir: [type: :string, required: true],
      issue_number: [type: :integer, required: true],
      issue_url: [type: :string, required: true],
      issue_brief: [type: {:or, [:string, nil]}, default: nil],
      writer_draft_v1: [type: {:or, [:string, nil]}, default: nil],
      writer_draft_v2: [type: {:or, [:string, nil]}, default: nil],
      critic_provider: [type: :atom, required: true],
      role_runtime_ready: [type: {:or, [:map, nil]}, default: nil],
      needs_revision: [type: {:or, [:boolean, nil]}, default: nil],
      timeout: [type: :integer, default: 300_000],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent],
      shell_session_server_mod: [type: :atom, default: Jido.Shell.ShellSessionServer],
      repo: [type: :string, required: true],
      owner: [type: :string, required: true],
      workspace_dir: [type: {:or, [:string, nil]}, default: nil],
      sprite_name: [type: {:or, [:string, nil]}, default: nil],
      sprite_config: [type: {:or, [:map, nil]}, default: nil],
      sprites_mod: [type: :atom, default: Sprites]
    ]

  alias Jido.Lib.Bots.Foundation.ArtifactStore
  alias Jido.Lib.Bots.Foundation.CritiqueSchema
  alias Jido.Lib.Bots.Foundation.RoleRunner
  alias Jido.Lib.Github.Actions.TriageCritic.Helpers

  @impl true
  def run(params, _context) do
    iteration = params.iteration

    cond do
      iteration not in [1, 2] ->
        {:error, {:run_critic_pass_failed, :invalid_iteration}}

      iteration == 2 and params[:needs_revision] != true ->
        {:ok, Helpers.pass_through(params)}

      true ->
        run_iteration(params, iteration)
    end
  end

  defp run_iteration(params, iteration) do
    provider = params.critic_provider

    with :ok <- ensure_runtime_ready(provider, params),
         {:ok, result} <-
           RoleRunner.run(
             role: :critic,
             provider: provider,
             session_id: params.session_id,
             repo_dir: params.repo_dir,
             run_id: params.run_id,
             prompt_file: "/tmp/jido_critic_#{params.run_id}_v#{iteration}.txt",
             prompt: critic_prompt(params, iteration),
             timeout: params[:timeout] || 300_000,
             shell_agent_mod: params[:shell_agent_mod] || Jido.Shell.Agent,
             shell_session_server_mod:
               params[:shell_session_server_mod] || Jido.Shell.ShellSessionServer
           ),
         {:ok, critique} <- CritiqueSchema.from_output(result.summary),
         {:ok, store} <- Helpers.artifact_store(params),
         {:ok, artifact} <-
           ArtifactStore.write_json(
             store,
             Helpers.critic_artifact_name(iteration),
             CritiqueSchema.to_map(critique)
           ) do
      key = Helpers.iteration_atom(iteration, :critic)

      {:ok,
       params
       |> Helpers.put_artifact(key, artifact)
       |> Map.put(key, CritiqueSchema.to_map(critique))}
    else
      {:error, reason} -> {:error, {:run_critic_pass_failed, reason}}
    end
  end

  defp ensure_runtime_ready(provider, params) do
    runtime_ready = params[:role_runtime_ready] || %{}

    if Map.get(runtime_ready, provider) == true do
      :ok
    else
      {:error, {:provider_runtime_not_ready, provider}}
    end
  end

  defp critic_prompt(params, iteration) do
    draft = if(iteration == 1, do: params[:writer_draft_v1], else: params[:writer_draft_v2]) || ""

    """
    You are the critic in a writer/critic issue triage workflow.

    Evaluate the writer draft for correctness, risk, completeness, and actionability.

    Issue brief:
    #{params[:issue_brief] || ""}

    Writer draft:
    #{draft}

    Return ONLY valid JSON with this exact shape:
    {
      "verdict": "accept" | "revise" | "reject",
      "severity": "low" | "medium" | "high" | "critical",
      "findings": [{"id": "short-id", "message": "...", "impact": "..."}],
      "revision_instructions": "specific instructions for writer",
      "confidence": 0.0
    }

    No markdown. No prose outside JSON.
    """
    |> String.trim()
  end
end
