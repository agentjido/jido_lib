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
    title = Map.get(fm, :title, "Untitled")
    audience = Map.get(fm, :audience, "beginner")
    ecosystem = Enum.map_join(Map.get(fm, :ecosystem_packages, []), ", ", &":#{&1}")

    intent = Map.get(overrides, :document_intent, "")

    required_sections =
      overrides
      |> Map.get(:required_sections, [])
      |> Enum.map_join("\n", &"- #{&1}")

    must_include =
      overrides
      |> Map.get(:must_include, [])
      |> Enum.map_join("\n", &"- #{&1}")

    must_avoid =
      overrides
      |> Map.get(:must_avoid, [])
      |> Enum.map_join("\n", &"- #{&1}")

    sections = [
      if(title != "Untitled", do: "**Title:** #{title}"),
      if(audience != "beginner", do: "**Audience:** #{audience}"),
      if(ecosystem != "", do: "**Ecosystem Packages:** [#{ecosystem}]"),
      if(intent != "", do: "## Document Intent\n#{intent}"),
      if(required_sections != "", do: "## Required Sections\n#{required_sections}"),
      if(must_include != "", do: "## Must Include\n#{must_include}"),
      if(must_avoid != "", do: "## Must Avoid\n#{must_avoid}")
    ]

    case Enum.reject(sections, &is_nil/1) do
      [] -> brief
      parts -> brief <> "\n\n## Content Plan Overrides\n\n" <> Enum.join(parts, "\n\n")
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
