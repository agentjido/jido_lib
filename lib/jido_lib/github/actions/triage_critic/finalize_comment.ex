defmodule Jido.Lib.Github.Actions.TriageCritic.FinalizeComment do
  @moduledoc """
  Finalizes triage comment output, posts optional issue comment, and persists run manifest.
  """

  use Jido.Action,
    name: "triage_critic_finalize_comment",
    description: "Finalize issue triage critic outputs and optional GitHub comment",
    compensation: [max_retries: 0],
    schema: [
      run_id: [type: :string, required: true],
      issue_url: [type: :string, required: true],
      owner: [type: :string, required: true],
      repo: [type: :string, required: true],
      issue_number: [type: :integer, required: true],
      writer_provider: [type: :atom, required: true],
      critic_provider: [type: :atom, required: true],
      post_comment: [type: :boolean, default: true],
      max_revisions: [type: :integer, default: 1],
      writer_draft_v1: [type: {:or, [:string, nil]}, default: nil],
      writer_draft_v2: [type: {:or, [:string, nil]}, default: nil],
      critique_v1: [type: {:or, [:map, nil]}, default: nil],
      critique_v2: [type: {:or, [:map, nil]}, default: nil],
      gate_v1: [type: {:or, [:map, nil]}, default: nil],
      gate_v2: [type: {:or, [:map, nil]}, default: nil],
      final_decision: [type: {:or, [:atom, nil]}, default: nil],
      needs_revision: [type: {:or, [:boolean, nil]}, default: nil],
      iterations_used: [type: {:or, [:integer, nil]}, default: nil],
      artifacts: [type: {:or, [:map, nil]}, default: nil],
      started_at: [type: {:or, [:string, nil]}, default: nil],
      repo_dir: [type: {:or, [:string, nil]}, default: nil],
      workspace_dir: [type: {:or, [:string, nil]}, default: nil],
      session_id: [type: {:or, [:string, nil]}, default: nil],
      sprite_name: [type: {:or, [:string, nil]}, default: nil],
      sprite_config: [type: {:or, [:map, nil]}, default: nil],
      sprites_mod: [type: :atom, default: Sprites],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent]
    ]

  alias Jido.Lib.Bots.Foundation.ArtifactStore
  alias Jido.Lib.Github.Actions.PostIssueComment
  alias Jido.Lib.Github.Actions.TriageCritic.Helpers

  @impl true
  def run(params, _context) do
    decision = params[:final_decision] || infer_decision(params)
    final_comment = build_final_comment(params, decision)
    iterations_used = infer_iterations(params)

    with {:ok, store} <- Helpers.artifact_store(params),
         {:ok, final_comment_artifact} <-
           ArtifactStore.write_text(store, "final_comment.md", final_comment),
         {:ok, publish} <- maybe_publish_comment(params, final_comment, decision),
         {:ok, manifest_artifact} <-
           write_manifest(
             store,
             params,
             decision,
             iterations_used,
             final_comment_artifact,
             publish
           ) do
      artifacts =
        params
        |> Map.get(:artifacts)
        |> case do
          map when is_map(map) -> map
          _ -> %{}
        end
        |> Map.put(:final_comment, final_comment_artifact)
        |> Map.put(:manifest, manifest_artifact)

      {:ok,
       Helpers.pass_through(params)
       |> Map.put(:final_decision, decision)
       |> Map.put(:decision, decision)
       |> Map.put(:iterations_used, iterations_used)
       |> Map.put(:final_comment, final_comment)
       |> Map.put(:comment_posted, publish.comment_posted)
       |> Map.put(:comment_url, publish.comment_url)
       |> Map.put(:comment_error, publish.comment_error)
       |> Map.put(:artifacts, artifacts)
       |> Map.put(:status, status_from_decision(decision))}
    else
      {:error, reason} ->
        {:error, {:finalize_comment_failed, reason}}
    end
  end

  defp maybe_publish_comment(%{post_comment: true} = params, final_comment, decision)
       when decision in [:accepted, :revised, :rejected] do
    post_params = %{
      comment_mode: :triage_report,
      owner: params.owner,
      repo: params.repo,
      provider: params.writer_provider,
      issue_number: params.issue_number,
      run_id: params.run_id,
      session_id: params.session_id,
      repo_dir: params.repo_dir,
      workspace_dir: params.workspace_dir,
      investigation: final_comment,
      investigation_status: :ok,
      investigation_error: nil,
      timeout: 300_000,
      shell_agent_mod: params[:shell_agent_mod] || Jido.Shell.Agent
    }

    case Jido.Exec.run(PostIssueComment, post_params, %{}) do
      {:ok, result} ->
        {:ok,
         %{
           comment_posted: result[:comment_posted] == true,
           comment_url: result[:comment_url],
           comment_error: result[:comment_error]
         }}

      {:error, reason} ->
        {:ok, %{comment_posted: false, comment_url: nil, comment_error: inspect(reason)}}
    end
  end

  defp maybe_publish_comment(_params, _final_comment, _decision) do
    {:ok, %{comment_posted: false, comment_url: nil, comment_error: nil}}
  end

  defp write_manifest(store, params, decision, iterations_used, final_comment_artifact, publish) do
    manifest = %{
      run_id: params.run_id,
      bot: "issue_triage_critic",
      status: status_from_decision(decision),
      started_at: params[:started_at] || Helpers.now_iso8601(),
      finished_at: Helpers.now_iso8601(),
      issue_url: params.issue_url,
      issue_number: params.issue_number,
      providers: %{
        writer: params.writer_provider,
        critic: params.critic_provider
      },
      max_revisions: params.max_revisions,
      iterations_used: iterations_used,
      decision: decision,
      artifacts: Map.put(params[:artifacts] || %{}, :final_comment, final_comment_artifact),
      publish: publish,
      gate: %{
        v1: params[:gate_v1],
        v2: params[:gate_v2]
      }
    }

    ArtifactStore.write_json(store, "manifest.json", manifest)
  end

  defp build_final_comment(params, :rejected) do
    critique = params[:critique_v2] || params[:critique_v1] || %{}
    instructions = critique[:revision_instructions] || critique["revision_instructions"] || ""

    """
    ## Automated Triage Review

    The writer/critic workflow did not reach an accepted draft in the revision budget.

    Last critique guidance:
    #{instructions}

    ---
    <sub>Generated by Jido Issue Triage Critic Bot | Run ID: `#{params.run_id}`</sub>
    """
    |> String.trim()
  end

  defp build_final_comment(params, _decision) do
    draft =
      params[:writer_draft_v2] || params[:writer_draft_v1] || "No writer draft was generated."

    """
    #{String.trim(draft)}

    ---
    <sub>Generated by Jido Issue Triage Critic Bot | Run ID: `#{params.run_id}`</sub>
    """
    |> String.trim()
  end

  defp infer_decision(params) do
    cond do
      is_map(params[:gate_v2]) and is_atom(params.gate_v2[:decision]) -> params.gate_v2[:decision]
      is_map(params[:gate_v1]) and is_atom(params.gate_v1[:decision]) -> params.gate_v1[:decision]
      params[:needs_revision] == true -> :rejected
      true -> :failed
    end
  end

  defp infer_iterations(params) do
    cond do
      is_binary(params[:writer_draft_v2]) and params.writer_draft_v2 != "" -> 2
      is_integer(params[:iterations_used]) -> params.iterations_used
      true -> 1
    end
  end

  defp status_from_decision(decision) when decision in [:accepted, :revised], do: :completed
  defp status_from_decision(:rejected), do: :failed
  defp status_from_decision(:failed), do: :error
  defp status_from_decision(_), do: :error
end
