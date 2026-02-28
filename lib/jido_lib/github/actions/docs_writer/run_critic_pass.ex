defmodule Jido.Lib.Github.Actions.DocsWriter.RunCriticPass do
  @moduledoc """
  Executes critic pass and persists structured critique artifacts.
  """

  use Jido.Action,
    name: "docs_writer_run_critic_pass",
    description: "Run critic role and emit structured critique report",
    compensation: [max_retries: 0],
    schema: [
      iteration: [type: :integer, required: true],
      run_id: [type: :string, required: true],
      session_id: [type: :string, required: true],
      repo_dir: [type: :string, required: true],
      docs_brief: [type: {:or, [:string, nil]}, default: nil],
      writer_draft_v1: [type: {:or, [:string, nil]}, default: nil],
      writer_draft_v2: [type: {:or, [:string, nil]}, default: nil],
      execution_trace_v1: [type: {:or, [:string, nil]}, default: nil],
      execution_trace_v2: [type: {:or, [:string, nil]}, default: nil],
      critic_provider: [type: :atom, required: true],
      single_pass: [type: :boolean, default: false],
      role_runtime_ready: [type: {:or, [:map, nil]}, default: nil],
      needs_revision: [type: {:or, [:boolean, nil]}, default: nil],
      codex_phase: [type: :atom, default: :triage],
      codex_fallback_phase: [type: {:or, [:atom, nil]}, default: :coding],
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
  alias Jido.Lib.Github.Actions.DocsWriter.Helpers

  @impl true
  def run(params, _context) do
    iteration = params.iteration

    cond do
      iteration not in [1, 2] ->
        {:error, {:docs_run_critic_pass_failed, :invalid_iteration}}

      params[:single_pass] == true ->
        {:ok, Helpers.pass_through(params)}

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
             prompt_file: ".jido/prompts/jido_docs_critic_#{params.run_id}_v#{iteration}.txt",
             prompt: critic_prompt(params, iteration),
             phase: provider_phase(provider, params),
             fallback_phase: provider_fallback_phase(provider, params),
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
      {:error, reason} -> {:error, {:docs_run_critic_pass_failed, reason}}
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

    execution_trace =
      if(iteration == 1, do: params[:execution_trace_v1], else: params[:execution_trace_v2]) ||
        "No execution trace available."

    has_trace = is_binary(execution_trace) and execution_trace != "No execution trace available."

    compiler_section =
      if has_trace do
        """

        CRITICAL:
        We extracted the Elixir code from the Writer's draft and actually executed it
        in a real Elixir environment. Here is the deterministic result:

        <compiler_trace>
        #{execution_trace}
        </compiler_trace>

        RULES:
        - If the <compiler_trace> shows a FAILURE or CompileError, you MUST reject the draft
          with the verdict "revise".
        - Pass the exact compiler error in the `revision_instructions` so the Writer knows
          exactly what API it hallucinated and how to fix it based on the Source Context.
        - If the trace is a SUCCESS, evaluate the narrative for clarity, layout, and adherence
          to the Must Include/Must Avoid rules.
        """
      else
        ""
      end

    """
    You are the technical editor and critic in a writer/critic documentation workflow.
    You are an expert Elixir engineer.
    #{compiler_section}
    Evaluate the writer draft for correctness, clarity, completeness, technical accuracy,
    and operational safety for practitioners.

    Brief context:
    #{params[:docs_brief] || ""}

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

  defp provider_phase(:codex, params), do: params[:codex_phase] || :triage
  defp provider_phase(_provider, _params), do: :triage

  defp provider_fallback_phase(:codex, params), do: params[:codex_fallback_phase]
  defp provider_fallback_phase(_provider, _params), do: nil
end
