defmodule Jido.Lib.Github.Actions.PrBot.EnsureBranch do
  @moduledoc """
  Ensure the repo is on a fresh working branch based on the configured base branch.
  """

  use Jido.Action,
    name: "ensure_branch",
    description: "Create/switch to a PR branch from base branch",
    schema: [
      owner: [type: :string, required: true],
      repo: [type: :string, required: true],
      provider: [type: :atom, default: :claude],
      issue_number: [type: :integer, required: true],
      run_id: [type: :string, required: true],
      repo_dir: [type: :string, required: true],
      session_id: [type: :string, required: true],
      branch_prefix: [type: :string, default: "jido/prbot"],
      base_branch: [type: {:or, [:string, nil]}, default: nil],
      timeout: [type: :integer, default: 300_000],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent]
    ]

  alias Jido.Lib.Github.Actions.PrBot.Helpers

  @max_branch_attempts 8

  @impl true
  def run(params, _context) do
    agent_mod = params[:shell_agent_mod] || Jido.Shell.Agent
    timeout = params[:timeout] || 300_000

    with {:ok, base_branch} <- resolve_base_branch(params, agent_mod, timeout),
         :ok <-
           sync_base_branch(params.repo_dir, params.session_id, base_branch, agent_mod, timeout),
         {:ok, branch_name} <- ensure_unique_branch(params, base_branch, agent_mod, timeout),
         {:ok, base_sha} <-
           rev_parse(params.repo_dir, params.session_id, base_branch, agent_mod, timeout) do
      {:ok,
       Map.merge(Helpers.pass_through(params), %{
         base_branch: base_branch,
         branch_name: branch_name,
         base_sha: base_sha
       })}
    else
      {:error, reason} ->
        {:error, {:ensure_branch_failed, reason}}
    end
  end

  defp resolve_base_branch(params, agent_mod, timeout) do
    case params[:base_branch] do
      branch when is_binary(branch) and branch != "" ->
        {:ok, branch}

      _ ->
        cmd =
          "gh repo view #{params.owner}/#{params.repo} --json defaultBranchRef -q .defaultBranchRef.name"

        case Helpers.run_in_dir(agent_mod, params.session_id, params.repo_dir, cmd,
               timeout: timeout
             ) do
          {:ok, branch} when is_binary(branch) and branch != "" -> {:ok, branch}
          {:ok, _} -> {:error, :missing_default_branch}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp sync_base_branch(repo_dir, session_id, base_branch, agent_mod, timeout) do
    [
      "git fetch origin #{base_branch}",
      "git checkout #{base_branch}",
      "git pull --ff-only origin #{base_branch}"
    ]
    |> Enum.reduce_while(:ok, fn cmd, :ok ->
      case Helpers.run_in_dir(agent_mod, session_id, repo_dir, cmd, timeout: timeout) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {cmd, reason}}}
      end
    end)
  end

  defp ensure_unique_branch(params, base_branch, agent_mod, timeout) do
    base_name =
      "#{params[:branch_prefix] || "jido/prbot"}/issue-#{params.issue_number}-#{params.run_id}"

    do_ensure_unique_branch(params, base_branch, agent_mod, timeout, base_name, 0)
  end

  defp do_ensure_unique_branch(_params, _base_branch, _agent_mod, _timeout, _base_name, attempt)
       when attempt >= @max_branch_attempts do
    {:error, :branch_name_exhausted}
  end

  defp do_ensure_unique_branch(params, base_branch, agent_mod, timeout, base_name, attempt) do
    candidate =
      case attempt do
        0 -> base_name
        _ -> "#{base_name}-#{short_rand()}"
      end

    with {:ok, missing?} <-
           branch_missing?(params.repo_dir, params.session_id, candidate, agent_mod, timeout),
         true <- missing? do
      cmd = "git checkout -b #{candidate}"

      case Helpers.run_in_dir(agent_mod, params.session_id, params.repo_dir, cmd,
             timeout: timeout
           ) do
        {:ok, _} ->
          {:ok, candidate}

        {:error, reason} ->
          {:error, {:checkout_branch_failed, base_branch, candidate, reason}}
      end
    else
      {:ok, false} ->
        do_ensure_unique_branch(params, base_branch, agent_mod, timeout, base_name, attempt + 1)

      {:error, reason} ->
        {:error, reason}

      false ->
        do_ensure_unique_branch(params, base_branch, agent_mod, timeout, base_name, attempt + 1)
    end
  end

  defp branch_missing?(repo_dir, session_id, branch_name, agent_mod, timeout) do
    cmd = """
    if git show-ref --verify --quiet refs/heads/#{branch_name}; then
      echo exists
    elif git ls-remote --exit-code --heads origin #{branch_name} >/dev/null 2>&1; then
      echo exists
    else
      echo missing
    fi
    """

    case Helpers.run_in_dir(agent_mod, session_id, repo_dir, cmd, timeout: timeout) do
      {:ok, "missing"} -> {:ok, true}
      {:ok, "exists"} -> {:ok, false}
      {:ok, _} -> {:error, :branch_probe_failed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp rev_parse(repo_dir, session_id, ref, agent_mod, timeout) do
    cmd = "git rev-parse #{ref}"

    case Helpers.run_in_dir(agent_mod, session_id, repo_dir, cmd, timeout: timeout) do
      {:ok, sha} when is_binary(sha) and sha != "" -> {:ok, sha}
      {:ok, _} -> {:error, :rev_parse_failed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp short_rand do
    :crypto.strong_rand_bytes(2)
    |> Base.encode16(case: :lower)
  end
end
