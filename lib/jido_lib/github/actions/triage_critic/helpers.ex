defmodule Jido.Lib.Github.Actions.TriageCritic.Helpers do
  @moduledoc false

  alias Jido.Lib.Bots.Foundation.ArtifactStore
  alias Jido.Lib.Github.Helpers

  @extra_keys [
    :writer_provider,
    :critic_provider,
    :max_revisions,
    :post_comment,
    :role_runtime,
    :role_runtime_ready,
    :issue_brief,
    :writer_draft_v1,
    :writer_draft_v2,
    :critique_v1,
    :critique_v2,
    :gate_v1,
    :gate_v2,
    :final_decision,
    :needs_revision,
    :iterations_used,
    :final_comment,
    :artifacts,
    :manifest,
    :started_at
  ]

  @spec pass_through(map()) :: map()
  def pass_through(params) when is_map(params) do
    Helpers.pass_through(params, @extra_keys)
  end

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
end
