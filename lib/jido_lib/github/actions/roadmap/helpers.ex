defmodule Jido.Lib.Github.Actions.Roadmap.Helpers do
  @moduledoc false

  alias Jido.Lib.Github.Helpers

  @extra_keys [
    :repo,
    :repo_slug,
    :repo_dir,
    :stories_dirs,
    :traceability_file,
    :issue_query,
    :provider,
    :run_id,
    :max_items,
    :start_at,
    :end_at,
    :only,
    :include_completed,
    :auto_include_dependencies,
    :apply,
    :push,
    :open_pr,
    :markdown_items,
    :github_items,
    :merged_items,
    :dependency_graph,
    :queue,
    :queue_results,
    :quality_gate,
    :fix_loop,
    :committed_items,
    :push_result,
    :pr_result,
    :state_file,
    :summary,
    :outputs,
    :artifacts,
    :warnings
  ]

  @spec pass_through(map()) :: map()
  def pass_through(params) when is_map(params), do: Helpers.pass_through(params, @extra_keys)
end
