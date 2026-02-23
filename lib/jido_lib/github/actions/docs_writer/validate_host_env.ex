defmodule Jido.Lib.Github.Actions.DocsWriter.ValidateHostEnv do
  @moduledoc """
  Validates docs writer intake, host env contracts, and repository selection.
  """

  use Jido.Action,
    name: "docs_writer_validate_host_env",
    description: "Validate docs writer host env and intake payload",
    compensation: [max_retries: 0],
    schema: [
      run_id: [type: :string, required: true],
      brief: [type: :string, required: true],
      repos: [type: {:list, :string}, required: true],
      output_repo: [type: :string, required: true],
      output_path: [type: {:or, [:string, nil]}, default: nil],
      local_output_repo_dir: [type: {:or, [:string, nil]}, default: nil],
      publish: [type: :boolean, default: false],
      writer_provider: [type: :atom, required: true],
      critic_provider: [type: :atom, required: true],
      max_revisions: [type: :integer, default: 1],
      single_pass: [type: :boolean, default: false],
      codex_phase: [type: :atom, default: :triage],
      codex_fallback_phase: [type: {:or, [:atom, nil]}, default: :coding],
      sprite_name: [type: :string, required: true],
      workspace_root: [type: {:or, [:string, nil]}, default: nil],
      setup_commands: [type: {:list, :string}, default: []],
      keep_sprite: [type: :boolean, default: true],
      timeout: [type: :integer, default: 300_000],
      sprite_config: [type: :map, required: true],
      sprites_mod: [type: :atom, default: Sprites],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent],
      shell_session_mod: [type: :atom, default: Jido.Shell.ShellSession]
    ]

  alias Jido.Lib.Github.Actions.DocsWriter.Helpers, as: DocsHelpers
  alias Jido.Lib.Github.Actions.ValidateHostEnv

  @impl true
  def run(params, _context) do
    with :ok <- validate_revision_budget(params.max_revisions),
         :ok <- validate_brief(params.brief),
         :ok <- validate_publish_requirements(params.publish, params.output_path),
         :ok <- validate_codex_phase_options(params.codex_phase, params.codex_fallback_phase),
         {:ok, repo_specs} <- DocsHelpers.parse_repo_specs(params.repos),
         {:ok, output_repo_context} <-
           DocsHelpers.resolve_output_repo(repo_specs, params.output_repo),
         {:ok, output_path} <- DocsHelpers.sanitize_output_path(params.output_path),
         :ok <-
           validate_provider_env(
             params.writer_provider,
             params.critic_provider,
             params.single_pass == true
           ) do
      workspace_root =
        DocsHelpers.normalize_workspace_root(params.workspace_root, params.sprite_name)

      {:ok,
       DocsHelpers.pass_through(params)
       |> Map.put(:brief, String.trim(params.brief))
       |> Map.put(:repos, repo_specs)
       |> Map.put(:output_repo_context, output_repo_context)
       |> Map.put(:output_path, output_path)
       |> Map.put(:publish_requested, params.publish == true)
       |> Map.put(:workspace_root, workspace_root)
       |> Map.put(:provider, params.writer_provider)
       |> Map.put(:owner, output_repo_context.owner)
       |> Map.put(:repo, output_repo_context.repo)}
    else
      {:error, reason} ->
        {:error, {:docs_validate_host_env_failed, reason}}
    end
  end

  defp validate_provider_env(writer_provider, critic_provider, single_pass) do
    providers =
      if single_pass do
        [writer_provider]
      else
        [writer_provider, critic_provider]
      end

    providers
    |> Enum.uniq()
    |> Enum.reduce_while(:ok, fn provider, :ok ->
      case ValidateHostEnv.validate_host_env(provider) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {provider, reason}}}
      end
    end)
  end

  defp validate_revision_budget(max_revisions) when max_revisions in [0, 1], do: :ok
  defp validate_revision_budget(other), do: {:error, {:invalid_max_revisions, other}}

  defp validate_brief(value) when is_binary(value) do
    if String.trim(value) == "" do
      {:error, :empty_brief}
    else
      :ok
    end
  end

  defp validate_brief(_), do: {:error, :invalid_brief}

  defp validate_publish_requirements(true, nil), do: {:error, :missing_output_path_for_publish}
  defp validate_publish_requirements(_publish, _output_path), do: :ok

  defp validate_codex_phase_options(codex_phase, codex_fallback_phase) do
    with :ok <- validate_codex_phase(codex_phase, :codex_phase),
         :ok <- validate_codex_fallback_phase(codex_fallback_phase) do
      :ok
    end
  end

  defp validate_codex_phase(value, _field) when value in [:triage, :coding], do: :ok
  defp validate_codex_phase(value, field), do: {:error, {:invalid_codex_phase, field, value}}

  defp validate_codex_fallback_phase(nil), do: :ok

  defp validate_codex_fallback_phase(value),
    do: validate_codex_phase(value, :codex_fallback_phase)
end
