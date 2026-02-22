defmodule Jido.Lib.Github.Actions.TriageCritic.BuildIssueBrief do
  @moduledoc """
  Builds and persists issue brief artifact used by writer/critic passes.
  """

  use Jido.Action,
    name: "triage_critic_build_issue_brief",
    description: "Build issue brief markdown and persist artifact",
    compensation: [max_retries: 0],
    schema: [
      run_id: [type: :string, required: true],
      issue_url: [type: :string, required: true],
      owner: [type: :string, required: true],
      repo: [type: :string, required: true],
      issue_number: [type: :integer, required: true],
      issue_title: [type: {:or, [:string, nil]}, default: nil],
      issue_body: [type: {:or, [:string, nil]}, default: nil],
      issue_labels: [type: {:list, :string}, default: []],
      writer_provider: [type: :atom, required: true],
      critic_provider: [type: :atom, required: true],
      max_revisions: [type: :integer, default: 1],
      post_comment: [type: :boolean, default: true],
      repo_dir: [type: {:or, [:string, nil]}, default: nil],
      workspace_dir: [type: {:or, [:string, nil]}, default: nil],
      sprite_name: [type: {:or, [:string, nil]}, default: nil],
      sprite_config: [type: {:or, [:map, nil]}, default: nil],
      sprites_mod: [type: :atom, default: Sprites],
      started_at: [type: {:or, [:string, nil]}, default: nil]
    ]

  alias Jido.Lib.Bots.Foundation.ArtifactStore
  alias Jido.Lib.Github.Actions.TriageCritic.Helpers

  @impl true
  def run(params, _context) do
    with {:ok, store} <- Helpers.artifact_store(params),
         {:ok, artifact} <- ArtifactStore.write_text(store, "issue_brief.md", issue_brief(params)) do
      {:ok,
       params
       |> Helpers.put_artifact(:issue_brief, artifact)
       |> Map.put(:issue_brief, issue_brief(params))
       |> Map.put_new(:started_at, Helpers.now_iso8601())}
    else
      {:error, reason} -> {:error, {:build_issue_brief_failed, reason}}
    end
  end

  defp issue_brief(params) do
    title = params[:issue_title] || "Issue ##{params.issue_number}"
    labels = format_labels(params[:issue_labels] || [])

    """
    # Issue Brief

    - Repo: #{params.owner}/#{params.repo}
    - Issue: ##{params.issue_number}
    - URL: #{params.issue_url}
    - Title: #{title}
    - Labels: #{labels}
    - Writer Provider: #{params.writer_provider}
    - Critic Provider: #{params.critic_provider}
    - Max Revisions: #{params.max_revisions}

    ## Body

    #{String.trim(params[:issue_body] || "")}
    """
    |> String.trim()
  end

  defp format_labels([]), do: "(none)"
  defp format_labels(labels), do: Enum.join(labels, ", ")
end
