defmodule Jido.Lib.Github.Actions.Quality.CloneOrAttachRepo do
  @moduledoc """
  Clones remote targets or attaches to local repo paths for quality runs.
  """

  use Jido.Action,
    name: "quality_clone_or_attach_repo",
    description: "Clone or attach quality bot repo",
    compensation: [max_retries: 0],
    schema: [
      target_info: [type: :map, required: true],
      github_token: [type: {:or, [:string, nil]}, default: nil],
      timeout: [type: :integer, default: 300_000],
      session_id: [type: {:or, [:string, nil]}, default: nil],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent]
    ]

  alias Jido.Lib.Github.Actions.Common.CommandRunner
  alias Jido.Lib.Github.Actions.Quality.Helpers

  @impl true
  def run(params, _context) do
    target_info = params.target_info

    case target_info.kind do
      :local ->
        {:ok, Helpers.pass_through(params) |> Map.put(:repo_dir, target_info.path)}

      :github ->
        do_clone_repo(params, target_info)

      other ->
        {:error, {:quality_clone_or_attach_repo_failed, {:unsupported_target_kind, other}}}
    end
  end

  defp do_clone_repo(params, target_info) do
    repo_dir = target_info.path
    File.rm_rf(repo_dir)
    File.mkdir_p!(Path.dirname(repo_dir))

    clone_url =
      case params[:github_token] do
        token when is_binary(token) and token != "" ->
          "https://x-access-token:#{token}@github.com/#{target_info.owner}/#{target_info.repo}.git"

        _ ->
          "https://github.com/#{target_info.owner}/#{target_info.repo}.git"
      end

    cmd = "git clone #{clone_url} #{repo_dir}"

    case CommandRunner.run_local(cmd, repo_dir: ".", params: Map.put(params, :apply, true)) do
      {:ok, _result} ->
        {:ok, Helpers.pass_through(params) |> Map.put(:repo_dir, repo_dir)}

      {:error, reason} ->
        {:error, {:quality_clone_or_attach_repo_failed, reason}}
    end
  end
end
