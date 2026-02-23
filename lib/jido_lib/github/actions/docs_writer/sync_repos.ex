defmodule Jido.Lib.Github.Actions.DocsWriter.SyncRepos do
  @moduledoc """
  Clones or refreshes repository context set for docs generation.
  """

  use Jido.Action,
    name: "docs_writer_sync_repos",
    description: "Clone or refresh docs context repositories",
    compensation: [max_retries: 0],
    schema: [
      repos: [type: {:list, :map}, required: true],
      output_repo_context: [type: :map, required: true],
      workspace_dir: [type: :string, required: true],
      session_id: [type: :string, required: true],
      timeout: [type: :integer, default: 300_000],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent]
    ]

  alias Jido.Lib.Github.Actions.DocsWriter.Helpers, as: DocsHelpers
  alias Jido.Lib.Github.Helpers

  @impl true
  def run(params, _context) do
    agent_mod = params[:shell_agent_mod] || Jido.Shell.Agent
    timeout = params[:timeout] || 300_000

    with :ok <- ensure_workspace_dir(agent_mod, params.session_id, params.workspace_dir, timeout),
         {:ok, repo_contexts} <- sync_all_repos(params.repos, params, agent_mod, timeout),
         {:ok, output_repo_context} <-
           resolve_output_context(repo_contexts, params.output_repo_context) do
      {:ok,
       DocsHelpers.pass_through(params)
       |> Map.put(:repo_contexts, repo_contexts)
       |> Map.put(:output_repo_context, output_repo_context)
       |> Map.put(:repo_dir, output_repo_context.repo_dir)
       |> Map.put(:owner, output_repo_context.owner)
       |> Map.put(:repo, output_repo_context.repo)
       |> Map.put(:output_repo, output_repo_context.alias)}
    else
      {:error, reason} ->
        {:error, {:docs_sync_repos_failed, reason}}
    end
  end

  defp ensure_workspace_dir(agent_mod, session_id, workspace_dir, timeout) do
    cmd = "mkdir -p #{Helpers.escape_path(workspace_dir)}"

    case Helpers.run(agent_mod, session_id, cmd, timeout: timeout) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:workspace_dir_prepare_failed, reason}}
    end
  end

  defp sync_all_repos(repo_specs, params, agent_mod, timeout) do
    repo_specs
    |> Enum.reduce_while({:ok, []}, fn spec, {:ok, acc} ->
      case sync_repo(spec, params, agent_mod, timeout) do
        {:ok, context} -> {:cont, {:ok, [context | acc]}}
        {:error, reason} -> {:halt, {:error, {spec.slug, reason}}}
      end
    end)
    |> case do
      {:ok, contexts} -> {:ok, Enum.reverse(contexts)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp sync_repo(spec, params, agent_mod, timeout) do
    repo_dir = Path.join(params.workspace_dir, spec.rel_dir)
    escaped_repo_dir = Helpers.escape_path(repo_dir)

    with {:ok, default_branch} <- fetch_default_branch(spec, params, agent_mod, timeout),
         {:ok, sync_mode} <-
           ensure_checkout(spec, escaped_repo_dir, params, default_branch, agent_mod, timeout) do
      {:ok,
       spec
       |> Map.put(:repo_dir, repo_dir)
       |> Map.put(:default_branch, default_branch)
       |> Map.put(:sync_mode, sync_mode)}
    end
  end

  defp ensure_checkout(spec, escaped_repo_dir, params, default_branch, agent_mod, timeout) do
    case repo_present?(escaped_repo_dir, params, agent_mod, timeout) do
      {:ok, true} ->
        with :ok <- verify_origin_remote(spec, escaped_repo_dir, params, agent_mod, timeout),
             :ok <-
               sync_existing_repo(escaped_repo_dir, default_branch, params, agent_mod, timeout) do
          {:ok, :reused}
        end

      {:ok, false} ->
        with :ok <- clone_repo(spec, escaped_repo_dir, params, agent_mod, timeout),
             :ok <-
               sync_existing_repo(escaped_repo_dir, default_branch, params, agent_mod, timeout) do
          {:ok, :cloned}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp repo_present?(escaped_repo_dir, params, agent_mod, timeout) do
    cmd = "if [ -d #{escaped_repo_dir}/.git ]; then echo present; else echo missing; fi"

    case Helpers.run(agent_mod, params.session_id, cmd, timeout: timeout) do
      {:ok, "present"} -> {:ok, true}
      {:ok, "missing"} -> {:ok, false}
      {:ok, _} -> {:ok, false}
      {:error, reason} -> {:error, reason}
    end
  end

  defp clone_repo(spec, escaped_repo_dir, params, agent_mod, timeout) do
    clone_url = "https://github.com/#{spec.slug}.git"
    cmd = "git clone #{clone_url} #{escaped_repo_dir}"

    case Helpers.run(agent_mod, params.session_id, cmd, timeout: timeout) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:clone_failed, reason}}
    end
  end

  defp verify_origin_remote(spec, escaped_repo_dir, params, agent_mod, timeout) do
    cmd = "git -C #{escaped_repo_dir} remote get-url origin"

    case Helpers.run(agent_mod, params.session_id, cmd, timeout: timeout) do
      {:ok, output} when is_binary(output) ->
        if String.contains?(output, spec.slug) do
          :ok
        else
          {:error, {:remote_mismatch, String.trim(output)}}
        end

      {:error, reason} ->
        {:error, {:remote_probe_failed, reason}}
    end
  end

  defp sync_existing_repo(escaped_repo_dir, default_branch, params, agent_mod, timeout) do
    [
      "git -C #{escaped_repo_dir} fetch origin #{default_branch}",
      "git -C #{escaped_repo_dir} checkout #{default_branch}",
      "git -C #{escaped_repo_dir} pull --ff-only origin #{default_branch}"
    ]
    |> Enum.reduce_while(:ok, fn cmd, :ok ->
      case Helpers.run(agent_mod, params.session_id, cmd, timeout: timeout) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {cmd, reason}}}
      end
    end)
  end

  defp fetch_default_branch(spec, params, agent_mod, timeout) do
    cmd =
      "gh repo view #{spec.owner}/#{spec.repo} --json defaultBranchRef -q .defaultBranchRef.name"

    case Helpers.run(agent_mod, params.session_id, cmd, timeout: timeout) do
      {:ok, branch} when is_binary(branch) and branch != "" -> {:ok, branch}
      {:ok, _} -> {:error, :missing_default_branch}
      {:error, reason} -> {:error, {:default_branch_probe_failed, reason}}
    end
  end

  defp resolve_output_context(repo_contexts, selected)
       when is_list(repo_contexts) and is_map(selected) do
    matches =
      Enum.filter(repo_contexts, fn context ->
        context.slug == selected.slug or context.alias == selected.alias
      end)

    case matches do
      [match] -> {:ok, match}
      [] -> {:error, :output_repo_missing_after_sync}
      _ -> {:error, :output_repo_ambiguous_after_sync}
    end
  end
end
