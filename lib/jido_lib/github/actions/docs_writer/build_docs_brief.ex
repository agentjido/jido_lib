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
      brief: [type: {:or, [:string, nil]}, default: nil],
      brief_body: [type: {:or, [:string, nil]}, default: nil],
      repos: [type: {:list, :map}, required: true],
      output_repo_context: [type: :map, required: true],
      output_path: [type: {:or, [:string, nil]}, default: nil],
      writer_provider: [type: :atom, required: true],
      critic_provider: [type: :atom, required: true],
      max_revisions: [type: :integer, default: 1],
      single_pass: [type: :boolean, default: false],
      publish: [type: :boolean, default: false],
      repo_dir: [type: {:or, [:string, nil]}, default: nil],
      workspace_dir: [type: {:or, [:string, nil]}, default: nil],
      sprite_name: [type: {:or, [:string, nil]}, default: nil],
      sprite_config: [type: {:or, [:map, nil]}, default: nil],
      sprites_mod: [type: :atom, default: Sprites],
      started_at: [type: {:or, [:string, nil]}, default: nil],
      # Grounded pipeline keys
      content_metadata: [type: {:or, [:map, nil]}, default: nil],
      prompt_overrides: [type: {:or, [:map, nil]}, default: nil],
      grounded_context: [type: {:or, [:string, nil]}, default: nil]
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
    fm = params[:content_metadata] || %{}
    overrides = params[:prompt_overrides] || %{}
    brief_body = params[:brief_body] || params[:brief] || ""

    base_brief = """
    # Documentation Guide Brief

    - Run ID: #{params.run_id}
    - Output Repo: #{output_repo}
    - Output Path: #{params[:output_path] || "(return text only)"}
    - Publish Requested: #{params.publish == true}
    - Writer Provider: #{params.writer_provider}
    - Critic Provider: #{params.critic_provider}
    - Max Revisions: #{params.max_revisions}
    - Single Pass: #{params.single_pass == true}

    ## Repository Context

    #{render_repo_context(params.repos)}

    ## Content Brief

    #{String.trim(brief_body)}
    """

    # Append grounded overrides if content_metadata is present
    base_brief
    |> maybe_append_overrides(fm, overrides)
    |> maybe_append_grounded_context(params[:grounded_context])
    |> String.trim()
  end

  defp render_repo_context(repo_specs) when is_list(repo_specs) do
    repo_specs
    |> Enum.map_join("\n", fn spec ->
      "- #{spec.slug} (alias: #{spec.alias})"
    end)
  end

  defp maybe_append_overrides(brief, fm, overrides)
       when map_size(fm) == 0 and map_size(overrides) == 0,
       do: brief

  defp maybe_append_overrides(brief, fm, overrides) do
    case override_sections(fm, overrides) do
      [] -> brief
      parts -> brief <> "\n\n## Content Plan Overrides\n\n" <> Enum.join(parts, "\n\n")
    end
  end

  defp override_sections(fm, overrides) do
    [
      metadata_override(:title, fm, "Untitled", "**Title:**"),
      metadata_override(:audience, fm, "beginner", "**Audience:**"),
      ecosystem_override(fm),
      text_override(:document_intent, overrides, "## Document Intent"),
      list_override(:required_sections, overrides, "## Required Sections"),
      list_override(:must_include, overrides, "## Must Include"),
      list_override(:must_avoid, overrides, "## Must Avoid")
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp metadata_override(key, metadata, default, label) do
    value = Map.get(metadata, key, default)

    if value == default do
      nil
    else
      "#{label} #{value}"
    end
  end

  defp ecosystem_override(metadata) do
    ecosystem =
      metadata
      |> Map.get(:ecosystem_packages, [])
      |> Enum.map_join(", ", &":#{&1}")

    if ecosystem == "" do
      nil
    else
      "**Ecosystem Packages:** [#{ecosystem}]"
    end
  end

  defp text_override(key, overrides, heading) do
    value = Map.get(overrides, key, "")

    if value == "" do
      nil
    else
      "#{heading}\n#{value}"
    end
  end

  defp list_override(key, overrides, heading) do
    value =
      overrides
      |> Map.get(key, [])
      |> Enum.map_join("\n", &"- #{&1}")

    if value == "" do
      nil
    else
      "#{heading}\n#{value}"
    end
  end

  defp maybe_append_grounded_context(brief, nil), do: brief
  defp maybe_append_grounded_context(brief, ""), do: brief

  defp maybe_append_grounded_context(brief, grounded_context) do
    brief <>
      """

      ## Grounded Sources (TRUTH)

      CRITICAL INSTRUCTION: Use the following exact source code to ensure all code examples
      are 100% accurate. DO NOT guess or hallucinate API signatures. Refer strictly to this context.

      #{grounded_context}
      """
  end
end
