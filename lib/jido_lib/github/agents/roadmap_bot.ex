defmodule Jido.Lib.Github.Agents.RoadmapBot do
  @moduledoc """
  Dependency-aware roadmap execution bot with dry-run defaults.
  """

  use Jido.Agent,
    name: "github_roadmap_bot",
    strategy: {Jido.Runic.Strategy, workflow_fn: &__MODULE__.build_workflow/0},
    schema: []

  alias Jido.Lib.Bots.Foundation.Intake
  alias Jido.Lib.Bots.{Result, Runtime}
  alias Jido.Lib.Github.Actions
  alias Jido.Lib.Github.Actions.Roadmap
  alias Jido.Lib.Github.AgentRuntime
  alias Jido.Lib.Github.Helpers
  alias Jido.Lib.Github.Plugins.{Observability, RuntimeContext}
  alias Runic.Workflow

  @default_timeout_ms 900_000
  @await_buffer_ms 60_000

  @doc false
  @spec plugin_specs() :: [Jido.Plugin.Spec.t()]
  def plugin_specs do
    [
      Observability.plugin_spec(%{}),
      RuntimeContext.plugin_spec(%{})
    ]
  end

  @doc "Build roadmap workflow DAG."
  @spec build_workflow() :: Workflow.t()
  def build_workflow do
    Workflow.new(name: :github_roadmap_bot)
    |> Workflow.add(Actions.node(Roadmap.ValidateRoadmapEnv))
    |> Workflow.add(Actions.node(Roadmap.LoadMarkdownBacklog), to: :validate_roadmap_env)
    |> Workflow.add(Actions.node(Roadmap.LoadGithubIssues), to: :load_markdown_backlog)
    |> Workflow.add(Actions.node(Roadmap.MergeRoadmapSources), to: :load_github_issues)
    |> Workflow.add(Actions.node(Roadmap.BuildDependencyGraph), to: :merge_roadmap_sources)
    |> Workflow.add(Actions.node(Roadmap.SelectWorkQueue), to: :build_dependency_graph)
    |> Workflow.add(Actions.node(Roadmap.ExecuteQueueLoop), to: :select_work_queue)
    |> Workflow.add(Actions.node(Roadmap.RunPerItemQualityGate), to: :execute_queue_loop)
    |> Workflow.add(Actions.node(Roadmap.RunPerItemFixLoop), to: :run_per_item_quality_gate)
    |> Workflow.add(Actions.node(Roadmap.CommitPerItem), to: :run_per_item_fix_loop)
    |> Workflow.add(Actions.node(Roadmap.PushOrOpenPr), to: :commit_per_item)
    |> Workflow.add(Actions.node(Roadmap.EmitRoadmapReport), to: :push_or_open_pr)
  end

  @doc "Build a runic intake signal from payload."
  @spec intake_signal(map()) :: Jido.Signal.t()
  def intake_signal(payload) when is_map(payload) do
    Jido.Signal.new!("runic.feed", %{data: payload}, source: "/github/roadmap_bot")
  end

  @doc "Run roadmap workflow for repo slug (owner/repo) or local path."
  @spec run_plan(String.t(), keyword()) :: map()
  def run_plan(repo, opts \\ []) when is_binary(repo) and is_list(opts) do
    run_id = Intake.normalize_run_id(Keyword.get(opts, :run_id))
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)

    intake = %{
      repo: repo,
      run_id: run_id,
      provider: Intake.normalize_provider(Keyword.get(opts, :provider, :codex), :codex),
      timeout: timeout,
      stories_dirs: normalize_stories_dirs(Keyword.get(opts, :stories_dirs, ["specs/stories"])),
      traceability_file: Keyword.get(opts, :traceability_file),
      issue_query: Keyword.get(opts, :issue_query),
      max_items: Keyword.get(opts, :max_items),
      start_at: Keyword.get(opts, :start_at),
      end_at: Keyword.get(opts, :end_at),
      only: Keyword.get(opts, :only),
      include_completed: Keyword.get(opts, :include_completed, false),
      auto_include_dependencies: Keyword.get(opts, :auto_include_dependencies, true),
      apply: Keyword.get(opts, :apply, false),
      push: Keyword.get(opts, :push, false),
      open_pr: Keyword.get(opts, :open_pr, false),
      baseline: Keyword.get(opts, :baseline, "generic_package_qa_v1"),
      quality_policy_path: Keyword.get(opts, :quality_policy_path),
      sprite_config: Keyword.get(opts, :sprite_config),
      github_token: Keyword.get(opts, :github_token),
      observer_pid: Keyword.get(opts, :observer_pid)
    }

    case run(intake,
           jido: Keyword.get(opts, :jido, Jido.Default),
           timeout: timeout + @await_buffer_ms,
           observer_pid: Keyword.get(opts, :observer_pid),
           debug: Keyword.get(opts, :debug, true)
         ) do
      {:ok, result} -> result
      {:error, reason, partial} when is_map(partial) -> Map.put(partial, :error, reason)
      {:error, reason} -> Result.fallback(:roadmap, intake, reason)
    end
  end

  @doc "Run roadmap bot from intake map."
  @spec run(map(), keyword()) :: {:ok, map()} | {:error, term(), map()} | {:error, term()}
  def run(intake, opts \\ []) when is_map(intake) and is_list(opts) do
    jido = Keyword.fetch!(opts, :jido)
    runtime_intake = Map.put_new(intake, :jido, jido)
    timeout = Keyword.get(opts, :timeout, Helpers.map_get(intake, :timeout, @default_timeout_ms))

    case Runtime.run_pipeline(__MODULE__, runtime_intake,
           jido: jido,
           timeout: timeout,
           debug: Keyword.get(opts, :debug, true),
           observer_pid: Keyword.get(opts, :observer_pid),
           sprite_prefix: "jido-roadmap"
         ) do
      {:ok, run} ->
        final = AgentRuntime.extract_final_production(run.productions)
        {:ok, Result.from_run(:roadmap, runtime_intake, run, final)}

      {:error, reason, run} ->
        final = AgentRuntime.extract_final_production(run.productions)
        {:error, reason, Result.from_run(:roadmap, runtime_intake, run, final)}
    end
  rescue
    error ->
      {:error, error}
  end

  defp normalize_stories_dirs(nil), do: ["specs/stories"]
  defp normalize_stories_dirs(value) when is_binary(value), do: [value]

  defp normalize_stories_dirs(values) when is_list(values) do
    values
    |> Enum.flat_map(fn
      value when is_binary(value) -> [value]
      _ -> []
    end)
    |> case do
      [] -> ["specs/stories"]
      dirs -> dirs
    end
  end

  defp normalize_stories_dirs(_), do: ["specs/stories"]
end
