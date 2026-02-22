defmodule Jido.Lib.Github.Actions.Release.Helpers do
  @moduledoc false

  alias Jido.Lib.Github.Helpers

  @extra_keys [
    :repo,
    :repo_dir,
    :owner,
    :provider,
    :release_type,
    :dry_run,
    :publish,
    :hex_api_key,
    :github_token,
    :sprites_token,
    :version_bump,
    :next_version,
    :changelog,
    :quality_result,
    :release_checks,
    :release_plan,
    :artifacts,
    :outputs,
    :summary
  ]

  @spec pass_through(map()) :: map()
  def pass_through(params) when is_map(params), do: Helpers.pass_through(params, @extra_keys)
end
