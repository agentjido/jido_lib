defmodule Jido.Lib.Github.Actions.TriageCritic.RunWriterPass do
  @moduledoc """
  Executes a writer pass and persists the writer draft artifact.
  """

  use Jido.Action,
    name: "triage_critic_run_writer_pass",
    description: "Run writer role for issue triage comment draft",
    compensation: [max_retries: 0],
    schema: [
      iteration: [type: :integer, required: true],
      run_id: [type: :string, required: true],
      session_id: [type: :string, required: true],
      repo_dir: [type: :string, required: true],
      issue_number: [type: :integer, required: true],
      issue_url: [type: :string, required: true],
      issue_title: [type: {:or, [:string, nil]}, default: nil],
      issue_body: [type: {:or, [:string, nil]}, default: nil],
      issue_labels: [type: {:list, :string}, default: []],
      issue_brief: [type: {:or, [:string, nil]}, default: nil],
      writer_provider: [type: :atom, required: true],
      critic_provider: [type: :atom, required: true],
      critique_v1: [type: {:or, [:map, nil]}, default: nil],
      needs_revision: [type: {:or, [:boolean, nil]}, default: nil],
      role_runtime_ready: [type: {:or, [:map, nil]}, default: nil],
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
  alias Jido.Lib.Bots.Foundation.RoleRunner
  alias Jido.Lib.Github.Actions.TriageCritic.Helpers

  @impl true
  def run(params, _context) do
    iteration = params.iteration

    cond do
      iteration not in [1, 2] ->
        {:error, {:run_writer_pass_failed, :invalid_iteration}}

      iteration == 2 and params[:needs_revision] != true ->
        {:ok, Helpers.pass_through(params)}

      true ->
        run_iteration(params, iteration)
    end
  end

  defp run_iteration(params, iteration) do
    provider = params.writer_provider

    with :ok <- ensure_runtime_ready(provider, params),
         {:ok, result} <-
           RoleRunner.run(
             role: :writer,
             provider: provider,
             session_id: params.session_id,
             repo_dir: params.repo_dir,
             run_id: params.run_id,
             prompt_file: "/tmp/jido_writer_#{params.run_id}_v#{iteration}.txt",
             prompt: writer_prompt(params, iteration),
             timeout: params[:timeout] || 300_000,
             shell_agent_mod: params[:shell_agent_mod] || Jido.Shell.Agent,
             shell_session_server_mod:
               params[:shell_session_server_mod] || Jido.Shell.ShellSessionServer
           ),
         {:ok, store} <- Helpers.artifact_store(params),
         {:ok, artifact} <-
           ArtifactStore.write_text(
             store,
             Helpers.writer_artifact_name(iteration),
             result.summary || ""
           ) do
      key = Helpers.iteration_atom(iteration, :writer)

      {:ok,
       params
       |> Helpers.put_artifact(key, artifact)
       |> Map.put(key, result.summary || "")
       |> Map.put(:iterations_used, iteration)}
    else
      {:error, reason} -> {:error, {:run_writer_pass_failed, reason}}
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

  defp writer_prompt(params, 1) do
    title = params[:issue_title] || "Issue ##{params.issue_number}"

    """
    You are the writer for an issue triage workflow.

    Use the following issue brief and draft a high-quality issue response comment.

    #{params[:issue_brief] || ""}

    Requirements:
    - Explain likely root cause from available evidence.
    - Propose a practical remediation path.
    - Include specific verification steps.
    - Be concise and technically precise.

    Return markdown only.

    Context:
    - Issue URL: #{params.issue_url}
    - Issue Title: #{title}
    """
    |> String.trim()
  end

  defp writer_prompt(params, 2) do
    instructions =
      get_in(params, [:critique_v1, :revision_instructions]) || "Address prior critique findings."

    """
    You are revising a triage response based on critic feedback.

    Original issue brief:
    #{params[:issue_brief] || ""}

    Previous draft:
    #{params[:writer_draft_v1] || ""}

    Critic revision instructions:
    #{instructions}

    Return only the improved markdown response comment.
    """
    |> String.trim()
  end
end
