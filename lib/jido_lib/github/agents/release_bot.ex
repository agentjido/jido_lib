defmodule Jido.Lib.Github.Agents.ReleaseBot do
  @moduledoc """
  Release preparation and publish bot.

  Runs in dry-run mode by default. Publish operations require explicit `publish: true`.
  """

  use Jido.Agent,
    name: "github_release_bot",
    strategy: {Jido.Runic.Strategy, workflow_fn: &__MODULE__.build_workflow/0},
    schema: []

  alias Jido.Lib.Bots.{Result, Runtime}
  alias Jido.Lib.Github.Actions
  alias Jido.Lib.Github.Actions.Release
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

  @doc "Build release workflow DAG."
  @spec build_workflow() :: Workflow.t()
  def build_workflow do
    Workflow.new(name: :github_release_bot)
    |> Workflow.add(Actions.node(Release.ValidateReleaseEnv))
    |> Workflow.add(Actions.node(Release.ProvisionSprite), to: :validate_release_env)
    |> Workflow.add(Actions.node(Release.CloneRepo), to: :provision_sprite)
    |> Workflow.add(Actions.node(Release.DetermineVersionBump), to: :clone_repo)
    |> Workflow.add(Actions.node(Release.GenerateChangelog), to: :determine_version_bump)
    |> Workflow.add(Actions.node(Release.ApplyReleaseFileUpdates), to: :generate_changelog)
    |> Workflow.add(Actions.node(Release.RunQualityGate), to: :apply_release_file_updates)
    |> Workflow.add(Actions.node(Release.RunReleaseChecks), to: :run_quality_gate)
    |> Workflow.add(Actions.node(Release.CommitReleaseArtifacts), to: :run_release_checks)
    |> Workflow.add(Actions.node(Release.CreateTag), to: :commit_release_artifacts)
    |> Workflow.add(Actions.node(Release.PushBranchAndTag), to: :create_tag)
    |> Workflow.add(Actions.node(Release.CreateGithubRelease), to: :push_branch_and_tag)
    |> Workflow.add(Actions.node(Release.PublishHex), to: :create_github_release)
    |> Workflow.add(Actions.node(Release.PostReleaseSummary), to: :publish_hex)
    |> Workflow.add(Actions.node(Release.TeardownWorkspace), to: :post_release_summary)
  end

  @doc "Build a runic intake signal from payload."
  @spec intake_signal(map()) :: Jido.Signal.t()
  def intake_signal(payload) when is_map(payload) do
    Jido.Signal.new!("runic.feed", %{data: payload}, source: "/github/release_bot")
  end

  @doc "Run release workflow for repo slug (owner/repo)."
  @spec run_repo(String.t(), keyword()) :: map()
  def run_repo(repo, opts \\ []) when is_binary(repo) and is_list(opts) do
    run_id = normalize_run_id(Keyword.get(opts, :run_id))
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)

    intake = %{
      repo: repo,
      owner: repo |> String.split("/", parts: 2) |> List.first(),
      run_id: run_id,
      provider: normalize_provider(Keyword.get(opts, :provider, :codex)),
      timeout: timeout,
      release_type: normalize_release_type(Keyword.get(opts, :release_type, :auto)),
      publish: Keyword.get(opts, :publish, false),
      apply: Keyword.get(opts, :publish, false),
      dry_run: Keyword.get(opts, :dry_run, true),
      github_token: Keyword.get(opts, :github_token),
      hex_api_key: Keyword.get(opts, :hex_api_key),
      sprites_token: Keyword.get(opts, :sprites_token),
      quality_policy_path: Keyword.get(opts, :quality_policy_path),
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
      {:error, reason} -> Result.fallback(:release, intake, reason)
    end
  end

  @doc "Run release bot from intake map."
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
           sprite_prefix: "jido-release"
         ) do
      {:ok, run} ->
        final = AgentRuntime.extract_final_production(run.productions)
        {:ok, Result.from_run(:release, runtime_intake, run, final)}

      {:error, reason, run} ->
        final = AgentRuntime.extract_final_production(run.productions)
        {:error, reason, Result.from_run(:release, runtime_intake, run, final)}
    end
  rescue
    error ->
      {:error, error}
  end

  defp normalize_provider(provider) do
    Helpers.provider_normalize!(provider)
  rescue
    _ -> :codex
  end

  defp normalize_release_type(type) when type in [:patch, :minor, :major, :auto], do: type
  defp normalize_release_type("patch"), do: :patch
  defp normalize_release_type("minor"), do: :minor
  defp normalize_release_type("major"), do: :major
  defp normalize_release_type("auto"), do: :auto
  defp normalize_release_type(_), do: :auto

  defp normalize_run_id(run_id) when is_binary(run_id) and run_id != "", do: run_id

  defp normalize_run_id(_run_id) do
    :crypto.strong_rand_bytes(6)
    |> Base.encode16(case: :lower)
  end
end
