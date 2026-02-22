defmodule Jido.Lib.Github.Actions.Common.MutationGuard do
  @moduledoc """
  Shared mutation guard for bot actions.

  Defaults to dry-run behavior unless explicit mutation flags are enabled.
  """

  @type reason :: :mutation_not_allowed | :publish_not_allowed

  @spec mutation_allowed?(map(), keyword()) :: boolean()
  def mutation_allowed?(params, opts \\ []) when is_map(params) and is_list(opts) do
    explicit_apply = params[:apply] == true or params["apply"] == true
    explicit_publish = params[:publish] == true or params["publish"] == true
    mode = params[:mode] || params["mode"]

    cond do
      Keyword.get(opts, :publish_only, false) ->
        explicit_publish

      mode in [:safe_fix, "safe_fix"] ->
        explicit_apply

      true ->
        explicit_apply or explicit_publish
    end
  end

  @spec require_mutation_allowed(map(), keyword()) :: :ok | {:error, reason()}
  def require_mutation_allowed(params, opts \\ []) when is_map(params) and is_list(opts) do
    if mutation_allowed?(params, opts) do
      :ok
    else
      {:error, :mutation_not_allowed}
    end
  end

  @spec require_publish_allowed(map()) :: :ok | {:error, reason()}
  def require_publish_allowed(params) when is_map(params) do
    if params[:publish] == true or params["publish"] == true do
      :ok
    else
      {:error, :publish_not_allowed}
    end
  end
end
