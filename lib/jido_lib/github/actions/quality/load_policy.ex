defmodule Jido.Lib.Github.Actions.Quality.LoadPolicy do
  @moduledoc """
  Loads baseline and override quality policy for the target repo.
  """

  use Jido.Action,
    name: "quality_load_policy",
    description: "Load quality policy",
    compensation: [max_retries: 0],
    schema: [
      repo_dir: [type: :string, required: true],
      policy_path: [type: {:or, [:string, nil]}, default: nil],
      baseline: [type: {:or, [:string, nil]}, default: nil]
    ]

  alias Jido.Lib.Bots.PolicyLoader
  alias Jido.Lib.Github.Actions.Quality.Helpers

  @impl true
  def run(params, _context) do
    case PolicyLoader.load(params.repo_dir,
           baseline: params[:baseline] || "generic_package_qa_v1",
           policy_path: params[:policy_path]
         ) do
      {:ok, policy} ->
        {:ok, Helpers.pass_through(params) |> Map.put(:policy, policy)}

      {:error, reason} ->
        {:error, {:quality_load_policy_failed, reason}}
    end
  end
end
