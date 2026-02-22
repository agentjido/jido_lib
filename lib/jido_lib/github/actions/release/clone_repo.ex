defmodule Jido.Lib.Github.Actions.Release.CloneRepo do
  @moduledoc """
  Clones release target repository.
  """

  use Jido.Action,
    name: "release_clone_repo",
    description: "Clone release target repo",
    compensation: [max_retries: 0],
    schema: [
      repo: [type: :string, required: true],
      github_token: [type: {:or, [:string, nil]}, default: nil],
      run_id: [type: :string, required: true]
    ]

  alias Jido.Lib.Bots.TargetResolver
  alias Jido.Lib.Github.Actions.Quality.CloneOrAttachRepo, as: QualityClone

  @impl true
  def run(params, context) do
    clone_dir = Path.join(System.tmp_dir!(), "jido-release-#{params.run_id}")

    case TargetResolver.resolve(params.repo, clone_dir: clone_dir) do
      {:ok, target_info} ->
        QualityClone.run(Map.put(params, :target_info, target_info), context)

      {:error, reason} ->
        {:error, {:release_clone_repo_failed, reason}}
    end
  end
end
