defmodule Jido.Lib.Github.Actions.Roadmap.ValidateRoadmapEnv do
  @moduledoc """
  Validates roadmap bot environment and required tools.
  """

  use Jido.Action,
    name: "roadmap_validate_env",
    description: "Validate roadmap env",
    compensation: [max_retries: 0],
    schema: [
      repo: [type: :string, required: true],
      run_id: [type: :string, required: true],
      github_token: [type: {:or, [:string, nil]}, default: nil],
      apply: [type: :boolean, default: false],
      push: [type: :boolean, default: false],
      open_pr: [type: :boolean, default: false]
    ]

  alias Jido.Lib.Bots.TargetResolver
  alias Jido.Lib.Github.Actions.Common.CommandRunner
  alias Jido.Lib.Github.Actions.Roadmap.Helpers
  alias Jido.Lib.Github.Helpers, as: GithubHelpers

  @required_tools ["git", "gh", "rg", "mix"]

  @impl true
  def run(params, _context) do
    missing = Enum.reject(@required_tools, &(System.find_executable(&1) != nil))

    if missing != [] do
      {:error, {:roadmap_validate_env_failed, {:missing_tools, missing}}}
    else
      resolve_repo(params)
    end
  end

  defp resolve_repo(params) do
    clone_dir = Path.join(System.tmp_dir!(), "jido-roadmap-#{params.run_id}")

    with {:ok, target_info} <- TargetResolver.resolve(params.repo, clone_dir: clone_dir),
         {:ok, repo_dir, repo_slug} <- ensure_repo_path(target_info, params) do
      {:ok,
       Helpers.pass_through(params)
       |> Map.put(:repo_dir, repo_dir)
       |> Map.put(:repo_slug, repo_slug)
       |> Map.put(
         :github_token,
         params[:github_token] || System.get_env("GH_TOKEN") || System.get_env("GITHUB_TOKEN")
       )}
    else
      {:error, reason} ->
        {:error, {:roadmap_validate_env_failed, reason}}
    end
  end

  defp ensure_repo_path(%{kind: :local, path: repo_dir}, _params) do
    {:ok, repo_dir, infer_repo_slug(repo_dir)}
  end

  defp ensure_repo_path(%{kind: :github} = target_info, params) do
    repo_dir = target_info.path
    File.rm_rf(repo_dir)
    File.mkdir_p!(Path.dirname(repo_dir))

    clone_url =
      case params[:github_token] || System.get_env("GH_TOKEN") || System.get_env("GITHUB_TOKEN") do
        token when is_binary(token) and token != "" ->
          "https://x-access-token:#{token}@github.com/#{target_info.owner}/#{target_info.repo}.git"

        _ ->
          "https://github.com/#{target_info.owner}/#{target_info.repo}.git"
      end

    cmd =
      "git clone #{GithubHelpers.shell_escape(clone_url)} #{GithubHelpers.shell_escape(repo_dir)}"

    case CommandRunner.run_local(cmd, repo_dir: ".", params: %{apply: true}) do
      {:ok, _result} ->
        {:ok, repo_dir, target_info.slug}

      {:error, reason} ->
        {:error, {:clone_failed, reason}}
    end
  end

  defp infer_repo_slug(repo_dir) do
    cmd = "cd #{GithubHelpers.escape_path(repo_dir)} && git remote get-url origin"

    with {output, 0} <- System.cmd("bash", ["-lc", cmd], stderr_to_stdout: true),
         slug when is_binary(slug) <- parse_slug(output) do
      slug
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp parse_slug(remote_url) when is_binary(remote_url) do
    remote_url
    |> String.trim()
    |> case do
      <<"git@github.com:", rest::binary>> -> normalize_slug(rest)
      <<"https://github.com/", rest::binary>> -> normalize_slug(rest)
      <<"http://github.com/", rest::binary>> -> normalize_slug(rest)
      _ -> nil
    end
  end

  defp normalize_slug(value) when is_binary(value) do
    slug = String.trim_trailing(value, ".git")

    if Regex.match?(~r/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/, slug) do
      slug
    else
      nil
    end
  end
end
