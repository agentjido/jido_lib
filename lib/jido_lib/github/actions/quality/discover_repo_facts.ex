defmodule Jido.Lib.Github.Actions.Quality.DiscoverRepoFacts do
  @moduledoc """
  Discovers repository facts used by policy evaluators.
  """

  use Jido.Action,
    name: "quality_discover_repo_facts",
    description: "Discover repo facts for quality checks",
    compensation: [max_retries: 0],
    schema: [
      repo_dir: [type: :string, required: true]
    ]

  alias Jido.Lib.Github.Actions.Quality.Helpers

  @required_files [
    "README.md",
    "mix.exs",
    "CHANGELOG.md",
    "LICENSE",
    "AGENTS.md",
    ".formatter.exs"
  ]

  @impl true
  def run(params, _context) do
    repo_dir = params.repo_dir

    file_presence =
      Map.new(@required_files, fn rel ->
        {rel, File.exists?(Path.join(repo_dir, rel))}
      end)

    facts = %{
      repo_dir: repo_dir,
      has_mix_project: File.exists?(Path.join(repo_dir, "mix.exs")),
      has_ci_workflow: File.exists?(Path.join(repo_dir, ".github/workflows/ci.yml")),
      has_release_workflow: File.exists?(Path.join(repo_dir, ".github/workflows/release.yml")),
      files: file_presence
    }

    {:ok,
     Helpers.pass_through(params)
     |> Map.put(:facts, facts)
     |> Map.put(:artifacts, [Path.join(repo_dir, ".jido")])}
  end
end
