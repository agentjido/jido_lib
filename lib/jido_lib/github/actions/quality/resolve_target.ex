defmodule Jido.Lib.Github.Actions.Quality.ResolveTarget do
  @moduledoc """
  Resolves quality bot target into local repo metadata.
  """

  use Jido.Action,
    name: "quality_resolve_target",
    description: "Resolve quality bot target",
    compensation: [max_retries: 0],
    schema: [
      target: [type: :string, required: true],
      run_id: [type: :string, required: true],
      provider: [type: :atom, default: :codex],
      mode: [type: :atom, default: :report],
      apply: [type: :boolean, default: false],
      github_token: [type: {:or, [:string, nil]}, default: nil]
    ]

  alias Jido.Lib.Bots.TargetResolver
  alias Jido.Lib.Github.Actions.Quality.Helpers

  @impl true
  def run(params, _context) do
    clone_dir = Path.join(System.tmp_dir!(), "jido-quality-#{params.run_id}")

    case TargetResolver.resolve(params.target, clone_dir: clone_dir) do
      {:ok, target_info} ->
        {:ok,
         Helpers.pass_through(params)
         |> Map.put(:target_info, target_info)
         |> Map.put(:owner, target_info.owner)
         |> Map.put(:repo, target_info.repo)
         |> Map.put(:repo_dir, target_info.path)}

      {:error, reason} ->
        {:error, {:quality_resolve_target_failed, reason}}
    end
  end
end
