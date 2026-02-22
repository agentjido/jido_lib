defmodule Jido.Lib.Github.Actions.Quality.Helpers do
  @moduledoc false

  alias Jido.Lib.Github.Helpers

  @extra_keys [
    :target,
    :target_info,
    :policy,
    :findings,
    :fix_plan,
    :applied_fixes,
    :validation_results,
    :report,
    :artifacts,
    :mode,
    :apply,
    :baseline,
    :policy_path,
    :github_token,
    :publish_comment,
    :summary,
    :outputs
  ]

  @spec pass_through(map()) :: map()
  def pass_through(params) when is_map(params), do: Helpers.pass_through(params, @extra_keys)

  @spec emit_signal(pid() | nil, module(), map()) :: :ok
  def emit_signal(pid, module, attrs) when is_pid(pid) and is_map(attrs) do
    signal = module.new!(attrs)
    send(pid, {:jido_lib_signal, signal})
    :ok
  rescue
    _ -> :ok
  end

  def emit_signal(_pid, _module, _attrs), do: :ok
end
