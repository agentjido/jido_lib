defmodule Jido.Lib.Github.Actions.DocsWriter.BuildDocsBrief do
  @moduledoc """
  Builds and persists docs brief artifact used by writer/critic passes.
  """

  use Jido.Action,
    name: "docs_writer_build_docs_brief",
    description: "Build docs brief markdown and persist artifact",
    compensation: [max_retries: 0],
    schema: [
      run_id: [type: :string, required: true],
      brief: [type: :string, required: true],
      repos: [type: {:list, :map}, required: true],
      output_repo_context: [type: :map, required: true],
      output_path: [type: {:or, [:string, nil]}, default: nil],
      writer_provider: [type: :atom, required: true],
      critic_provider: [type: :atom, required: true],
      max_revisions: [type: :integer, default: 1],
      publish: [type: :boolean, default: false],
      repo_dir: [type: {:or, [:string, nil]}, default: nil],
      workspace_dir: [type: {:or, [:string, nil]}, default: nil],
      sprite_name: [type: {:or, [:string, nil]}, default: nil],
      sprite_config: [type: {:or, [:map, nil]}, default: nil],
      sprites_mod: [type: :atom, default: Sprites],
      started_at: [type: {:or, [:string, nil]}, default: nil]
    ]

  alias Jido.Lib.Bots.Foundation.ArtifactStore
  alias Jido.Lib.Github.Actions.DocsWriter.Helpers

  @impl true
  def run(params, _context) do
    docs_brief = build_brief(params)

    with {:ok, store} <- Helpers.artifact_store(params),
         {:ok, artifact} <- ArtifactStore.write_text(store, "docs_brief.md", docs_brief) do
      {:ok,
       params
       |> Helpers.put_artifact(:docs_brief, artifact)
       |> Map.put(:docs_brief, docs_brief)
       |> Map.put_new(:started_at, Helpers.now_iso8601())}
    else
      {:error, reason} -> {:error, {:docs_build_docs_brief_failed, reason}}
    end
  end

  defp build_brief(params) do
    output_repo = params.output_repo_context.slug

    """
    # Documentation Guide Brief

    - Run ID: #{params.run_id}
    - Output Repo: #{output_repo}
    - Output Path: #{params[:output_path] || "(return text only)"}
    - Publish Requested: #{params.publish == true}
    - Writer Provider: #{params.writer_provider}
    - Critic Provider: #{params.critic_provider}
    - Max Revisions: #{params.max_revisions}

    ## Repository Context

    #{render_repo_context(params.repos)}

    ## Content Brief

    #{String.trim(params.brief)}
    """
    |> String.trim()
  end

  defp render_repo_context(repo_specs) when is_list(repo_specs) do
    repo_specs
    |> Enum.map_join("\n", fn spec ->
      "- #{spec.slug} (alias: #{spec.alias})"
    end)
  end
end
