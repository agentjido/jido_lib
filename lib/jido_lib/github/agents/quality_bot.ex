defmodule Jido.Lib.Github.Agents.QualityBot do
  @moduledoc """
  Policy-driven repository quality bot.

  Default mode is report-only; safe-fix mutations require explicit apply mode.
  """

  use Jido.Agent,
    name: "github_quality_bot",
    strategy: {Jido.Runic.Strategy, workflow_fn: &__MODULE__.build_workflow/0},
    schema: []

  alias Jido.Lib.Bots.Foundation.Intake
  alias Jido.Lib.Bots.{Result, Runtime}
  alias Jido.Lib.Github.Actions
  alias Jido.Lib.Github.AgentRuntime
  alias Jido.Lib.Github.Actions.Quality
  alias Jido.Lib.Github.Helpers
  alias Jido.Lib.Github.Plugins.{Observability, RuntimeContext}
  alias Runic.Workflow

  @default_timeout_ms 600_000
  @await_buffer_ms 60_000

  @doc false
  @spec plugin_specs() :: [Jido.Plugin.Spec.t()]
  def plugin_specs do
    [
      Observability.plugin_spec(%{}),
      RuntimeContext.plugin_spec(%{})
    ]
  end

  @doc "Build quality workflow DAG."
  @spec build_workflow() :: Workflow.t()
  def build_workflow do
    Workflow.new(name: :github_quality_bot)
    |> Workflow.add(Actions.node(Quality.ValidateHostEnv))
    |> Workflow.add(Actions.node(Quality.ResolveTarget), to: :validate_host_env)
    |> Workflow.add(Actions.node(Quality.ProvisionSprite), to: :resolve_target)
    |> Workflow.add(Actions.node(Quality.CloneOrAttachRepo), to: :provision_sprite)
    |> Workflow.add(Actions.node(Quality.LoadPolicy), to: :clone_or_attach_repo)
    |> Workflow.add(Actions.node(Quality.DiscoverRepoFacts), to: :load_policy)
    |> Workflow.add(Actions.node(Quality.EvaluateChecks), to: :discover_repo_facts)
    |> Workflow.add(Actions.node(Quality.PlanSafeFixes), to: :evaluate_checks)
    |> Workflow.add(Actions.node(Quality.ApplySafeFixes), to: :plan_safe_fixes)
    |> Workflow.add(Actions.node(Quality.RunValidationCommands), to: :apply_safe_fixes)
    |> Workflow.add(Actions.node(Quality.PublishQualityReport), to: :run_validation_commands)
    |> Workflow.add(Actions.node(Quality.TeardownWorkspace), to: :publish_quality_report)
  end

  @doc "Build a runic intake signal from payload."
  @spec intake_signal(map()) :: Jido.Signal.t()
  def intake_signal(payload) when is_map(payload) do
    Jido.Signal.new!("runic.feed", %{data: payload}, source: "/github/quality_bot")
  end

  @doc "Run quality bot for a target (local path or owner/repo slug)."
  @spec run_target(String.t(), keyword()) :: map()
  def run_target(target, opts \\ []) when is_binary(target) and is_list(opts) do
    run_id = Intake.normalize_run_id(Keyword.get(opts, :run_id))
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)

    intake = %{
      target: target,
      run_id: run_id,
      provider: Intake.normalize_provider(Keyword.get(opts, :provider, :codex), :codex),
      timeout: timeout,
      mode: if(Keyword.get(opts, :apply, false), do: :safe_fix, else: :report),
      apply: Keyword.get(opts, :apply, false),
      policy_path: Keyword.get(opts, :policy_path),
      baseline: Keyword.get(opts, :baseline, "generic_package_qa_v1"),
      github_token: Keyword.get(opts, :github_token),
      publish_comment: Keyword.get(opts, :publish_comment),
      observer_pid: Keyword.get(opts, :observer_pid),
      sprite_config: Keyword.get(opts, :sprite_config),
      shell_agent_mod: Keyword.get(opts, :shell_agent_mod, Jido.Shell.Agent),
      shell_session_mod: Keyword.get(opts, :shell_session_mod, Jido.Shell.ShellSession)
    }

    case run(intake,
           jido: Keyword.get(opts, :jido, Jido.Default),
           timeout: timeout + @await_buffer_ms,
           observer_pid: Keyword.get(opts, :observer_pid),
           debug: Keyword.get(opts, :debug, true)
         ) do
      {:ok, result} -> result
      {:error, reason, partial} when is_map(partial) -> Map.put(partial, :error, reason)
      {:error, reason} -> Result.fallback(:quality, intake, reason)
    end
  end

  @doc "Run quality bot from pre-built intake map."
  @spec run(map(), keyword()) :: {:ok, map()} | {:error, term(), map()} | {:error, term()}
  def run(intake, opts \\ []) when is_map(intake) and is_list(opts) do
    jido = Keyword.fetch!(opts, :jido)
    timeout = Keyword.get(opts, :timeout, Helpers.map_get(intake, :timeout, @default_timeout_ms))

    case Runtime.run_pipeline(__MODULE__, intake,
           jido: jido,
           timeout: timeout,
           debug: Keyword.get(opts, :debug, true),
           observer_pid: Keyword.get(opts, :observer_pid),
           sprite_prefix: "jido-quality"
         ) do
      {:ok, run} ->
        final = AgentRuntime.extract_final_production(run.productions)
        {:ok, Result.from_run(:quality, intake, run, final)}

      {:error, reason, run} ->
        final = AgentRuntime.extract_final_production(run.productions)
        {:error, reason, Result.from_run(:quality, intake, run, final)}
    end
  rescue
    error ->
      {:error, error}
  end
end
