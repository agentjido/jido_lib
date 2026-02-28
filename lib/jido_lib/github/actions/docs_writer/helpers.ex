defmodule Jido.Lib.Github.Actions.DocsWriter.Helpers do
  @moduledoc false

  alias Jido.Lib.Bots.Foundation.ArtifactStore
  alias Jido.Lib.Github.Helpers

  @extra_keys [
    :brief,
    :repos,
    :repo_contexts,
    :output_repo,
    :output_repo_context,
    :output_path,
    :local_output_repo_dir,
    :local_guide_path,
    :publish,
    :publish_requested,
    :published,
    :workspace_root,
    :sprite_origin,
    :docs_brief,
    :writer_provider,
    :critic_provider,
    :max_revisions,
    :single_pass,
    :codex_phase,
    :codex_fallback_phase,
    :role_runtime,
    :role_runtime_ready,
    :writer_draft_v1,
    :writer_draft_v2,
    :critique_v1,
    :critique_v2,
    :gate_v1,
    :gate_v2,
    :final_decision,
    :decision,
    :needs_revision,
    :iterations_used,
    :final_guide,
    :guide_path,
    :artifacts,
    :manifest,
    :started_at,
    :branch_name,
    :base_branch,
    :commit_sha,
    :pr_number,
    :pr_url,
    :pr_title,
    :status,
    :error,
    # Grounded documentation pipeline keys
    :content_metadata,
    :prompt_overrides,
    :brief_body,
    :grounded_sources,
    :grounded_context,
    :execution_trace_v1,
    :execution_trace_v2,
    :execution_feedback,
    :interactive_demo_block,
    :embedded_draft
  ]

  @repo_spec_regex ~r/^([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)(?::([A-Za-z0-9_.-]+))?$/
  @safe_root "/tmp/jido-docs-path-check"

  @spec pass_through(map()) :: map()
  def pass_through(params) when is_map(params), do: Helpers.pass_through(params, @extra_keys)

  @spec artifact_store(map()) :: {:ok, ArtifactStore.t()} | {:error, term()}
  def artifact_store(params) when is_map(params) do
    ArtifactStore.new(
      run_id: Helpers.map_get(params, :run_id),
      repo_dir: Helpers.map_get(params, :repo_dir),
      workspace_dir: Helpers.map_get(params, :workspace_dir),
      sprite_name: Helpers.map_get(params, :sprite_name),
      sprite_config: Helpers.map_get(params, :sprite_config),
      sprites_mod: Helpers.map_get(params, :sprites_mod, Sprites)
    )
  end

  @spec put_artifact(map(), atom(), map()) :: map()
  def put_artifact(params, key, artifact_meta)
      when is_map(params) and is_atom(key) and is_map(artifact_meta) do
    artifacts =
      params
      |> Helpers.map_get(:artifacts, %{})
      |> Map.put(key, artifact_meta)

    Map.put(pass_through(params), :artifacts, artifacts)
  end

  @spec parse_repo_specs(term()) :: {:ok, [map()]} | {:error, term()}
  def parse_repo_specs(specs) when is_list(specs) do
    with {:ok, parsed} <- parse_repo_specs_with_index(specs, 0, []),
         :ok <- ensure_unique_aliases(parsed) do
      {:ok, parsed}
    end
  end

  def parse_repo_specs(_), do: {:error, :invalid_repo_specs}

  @spec resolve_output_repo([map()], term()) :: {:ok, map()} | {:error, term()}
  def resolve_output_repo(repo_specs, output_repo)
      when is_list(repo_specs) and is_binary(output_repo) do
    candidate = String.trim(output_repo)

    if candidate == "" do
      {:error, :missing_output_repo}
    else
      matches =
        Enum.filter(repo_specs, fn spec ->
          spec.slug == candidate or spec.alias == candidate
        end)

      case matches do
        [match] -> {:ok, match}
        [] -> {:error, {:output_repo_not_found, candidate}}
        _ -> {:error, {:output_repo_ambiguous, candidate}}
      end
    end
  end

  def resolve_output_repo(_repo_specs, _output_repo), do: {:error, :missing_output_repo}

  @spec sanitize_output_path(term()) :: {:ok, String.t() | nil} | {:error, term()}
  def sanitize_output_path(nil), do: {:ok, nil}

  def sanitize_output_path(path) when is_binary(path) do
    trimmed = String.trim(path)

    cond do
      trimmed == "" ->
        {:error, :empty_output_path}

      Path.type(trimmed) == :absolute ->
        {:error, :absolute_output_path}

      true ->
        normalize_relative_path(trimmed)
    end
  end

  def sanitize_output_path(_), do: {:error, :invalid_output_path}

  @spec normalize_workspace_root(term(), String.t()) :: String.t()
  def normalize_workspace_root(root, sprite_name)
      when is_binary(root) and is_binary(sprite_name) do
    case String.trim(root) do
      "" -> "/work/docs/#{sprite_name}"
      value -> value
    end
  end

  def normalize_workspace_root(_root, sprite_name) when is_binary(sprite_name),
    do: "/work/docs/#{sprite_name}"

  @spec iteration_atom(pos_integer(), :writer | :critic) :: atom()
  def iteration_atom(1, :writer), do: :writer_draft_v1
  def iteration_atom(2, :writer), do: :writer_draft_v2
  def iteration_atom(1, :critic), do: :critique_v1
  def iteration_atom(2, :critic), do: :critique_v2

  @spec writer_artifact_name(pos_integer()) :: String.t()
  def writer_artifact_name(1), do: "writer_draft_v1.md"
  def writer_artifact_name(2), do: "writer_draft_v2.md"

  @spec critic_artifact_name(pos_integer()) :: String.t()
  def critic_artifact_name(1), do: "critic_report_v1.json"
  def critic_artifact_name(2), do: "critic_report_v2.json"

  @spec now_iso8601() :: String.t()
  def now_iso8601, do: DateTime.utc_now() |> DateTime.to_iso8601()

  @spec maybe_binary(term()) :: String.t() | nil
  def maybe_binary(value) when is_binary(value) and value != "", do: value
  def maybe_binary(_), do: nil

  defp parse_repo_specs_with_index([], _idx, acc), do: {:ok, Enum.reverse(acc)}

  defp parse_repo_specs_with_index([spec | rest], idx, acc) do
    case parse_repo_spec(spec) do
      {:ok, parsed} ->
        parse_repo_specs_with_index(rest, idx + 1, [Map.put(parsed, :index, idx) | acc])

      {:error, reason} ->
        {:error, {:invalid_repo_spec, spec, reason}}
    end
  end

  defp parse_repo_spec(spec) when is_binary(spec) do
    value = String.trim(spec)

    case Regex.run(@repo_spec_regex, value) do
      [_, slug, alias_name] ->
        [owner, repo] = String.split(slug, "/", parts: 2)
        alias_value = if(is_binary(alias_name) and alias_name != "", do: alias_name, else: repo)

        {:ok,
         %{
           owner: owner,
           repo: repo,
           slug: slug,
           alias: alias_value,
           rel_dir: alias_value
         }}

      _ ->
        {:error, :invalid_format}
    end
  end

  defp parse_repo_spec(_), do: {:error, :invalid_type}

  defp ensure_unique_aliases(repo_specs) when is_list(repo_specs) do
    aliases = Enum.map(repo_specs, & &1.alias)

    if length(aliases) == length(Enum.uniq(aliases)) do
      :ok
    else
      {:error, :duplicate_repo_alias}
    end
  end

  defp normalize_relative_path(path) when is_binary(path) do
    expanded = Path.expand(path, @safe_root)

    cond do
      expanded == @safe_root ->
        {:error, :invalid_output_path}

      not String.starts_with?(expanded, @safe_root <> "/") ->
        {:error, :output_path_traversal}

      true ->
        relative = Path.relative_to(expanded, @safe_root)

        if relative == "" or relative == "." do
          {:error, :invalid_output_path}
        else
          {:ok, relative}
        end
    end
  end
end
