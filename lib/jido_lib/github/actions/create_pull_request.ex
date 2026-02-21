defmodule Jido.Lib.Github.Actions.CreatePullRequest do
  @moduledoc """
  Create (or reuse) a GitHub pull request for the pushed branch.
  """

  use Jido.Action,
    name: "create_pull_request",
    description: "Create or reuse open PR for branch",
    compensation: [max_retries: 1],
    schema: [
      owner: [type: :string, required: true],
      repo: [type: :string, required: true],
      provider: [type: :atom, default: :claude],
      issue_number: [type: :integer, required: true],
      issue_url: [type: {:or, [:string, nil]}, default: nil],
      issue_title: [type: {:or, [:string, nil]}, default: nil],
      run_id: [type: :string, required: true],
      repo_dir: [type: :string, required: true],
      session_id: [type: :string, required: true],
      branch_name: [type: :string, required: true],
      base_branch: [type: :string, required: true],
      timeout: [type: :integer, default: 300_000],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent]
    ]

  alias Jido.Lib.Github.Helpers

  @impl true
  def run(params, _context) do
    agent_mod = params[:shell_agent_mod] || Jido.Shell.Agent
    timeout = params[:timeout] || 300_000

    case find_existing_pr(params, agent_mod, timeout) do
      {:ok, %{} = pr} ->
        {:ok,
         Map.merge(Helpers.pass_through(params), %{
           pr_created: false,
           pr_number: pr[:number],
           pr_url: pr[:url],
           pr_title: pr[:title]
         })}

      {:ok, nil} ->
        create_pr(params, agent_mod, timeout)

      {:error, reason} ->
        {:error, {:create_pull_request_failed, reason}}
    end
  end

  defp create_pr(params, agent_mod, timeout) do
    title = "Fix ##{params.issue_number}: #{params[:issue_title] || "Issue update"}"
    body = build_pr_body(params)
    body_file = "/tmp/jido_pr_body_#{params.run_id}.md"
    escaped_body_file = Helpers.escape_path(body_file)
    write_cmd = "cat > #{escaped_body_file} << 'JIDO_PR_BODY_EOF'\n#{body}\nJIDO_PR_BODY_EOF"

    with {:ok, _} <-
           Helpers.run_in_dir(agent_mod, params.session_id, params.repo_dir, write_cmd,
             timeout: 10_000
           ),
         {:ok, output} <- create_pr_cmd(params, title, escaped_body_file, agent_mod, timeout),
         {:ok, pr} <- resolve_pr_from_output_or_query(params, output, agent_mod, timeout) do
      {:ok,
       Map.merge(Helpers.pass_through(params), %{
         pr_created: true,
         pr_number: pr[:number],
         pr_url: pr[:url],
         pr_title: pr[:title] || title
       })}
    else
      {:error, reason} -> {:error, {:create_pull_request_failed, reason}}
    end
  end

  defp create_pr_cmd(params, title, escaped_body_file, agent_mod, timeout) do
    cmd =
      "gh pr create --repo #{params.owner}/#{params.repo} " <>
        "--base #{params.base_branch} --head #{params.branch_name} " <>
        "--title #{Helpers.shell_escape(title)} --body-file #{escaped_body_file}"

    Helpers.run_in_dir(agent_mod, params.session_id, params.repo_dir, cmd, timeout: timeout)
  end

  defp resolve_pr_from_output_or_query(params, output, agent_mod, timeout) do
    case extract_url(output) do
      nil ->
        with {:ok, existing} <- find_existing_pr(params, agent_mod, timeout),
             %{} = pr <- existing do
          {:ok, pr}
        else
          _ -> {:error, :missing_pr_url}
        end

      url ->
        number = extract_number(url)
        {:ok, %{url: url, number: number, title: nil}}
    end
  end

  defp find_existing_pr(params, agent_mod, timeout) do
    cmd =
      "gh pr list --repo #{params.owner}/#{params.repo} " <>
        "--head #{params.branch_name} --state open --json number,url,title"

    with {:ok, output} <-
           Helpers.run_in_dir(agent_mod, params.session_id, params.repo_dir, cmd,
             timeout: timeout
           ),
         {:ok, list} <- Jason.decode(output),
         true <- is_list(list) do
      case list do
        [first | _] when is_map(first) ->
          {:ok, %{number: first["number"], url: first["url"], title: first["title"]}}

        _ ->
          {:ok, nil}
      end
    else
      false -> {:error, :invalid_pr_list}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_pr_body(params) do
    """
    ## Automated PR from Jido PrBot

    Resolves issue ##{params.issue_number}
    Issue URL: #{params[:issue_url] || "unknown"}
    Run ID: #{params.run_id}
    Branch: #{params.branch_name}
    """
    |> String.trim()
  end

  defp extract_url(output) when is_binary(output) do
    case Regex.run(~r{https://github\.com/[^\s]+/pull/\d+}, output) do
      [url] -> url
      _ -> nil
    end
  end

  defp extract_number(url) when is_binary(url) do
    case Regex.run(~r{/pull/(\d+)}, url) do
      [_, number] -> String.to_integer(number)
      _ -> nil
    end
  end
end
