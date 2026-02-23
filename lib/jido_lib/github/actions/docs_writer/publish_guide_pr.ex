defmodule Jido.Lib.Github.Actions.DocsWriter.PublishGuidePr do
  @moduledoc """
  Optionally writes final guide to disk and publishes a PR in the output repository.
  """

  use Jido.Action,
    name: "docs_writer_publish_guide_pr",
    description: "Write guide and optionally open pull request",
    compensation: [max_retries: 0],
    schema: [
      publish: [type: :boolean, default: false],
      run_id: [type: :string, required: true],
      owner: [type: :string, required: true],
      repo: [type: :string, required: true],
      writer_provider: [type: {:or, [:atom, nil]}, default: nil],
      critic_provider: [type: {:or, [:atom, nil]}, default: nil],
      single_pass: [type: :boolean, default: false],
      output_path: [type: {:or, [:string, nil]}, default: nil],
      local_output_repo_dir: [type: {:or, [:string, nil]}, default: nil],
      final_guide: [type: {:or, [:string, nil]}, default: nil],
      repo_dir: [type: :string, required: true],
      session_id: [type: :string, required: true],
      branch_prefix: [type: :string, default: "jido/docs"],
      decision: [type: {:or, [:atom, nil]}, default: nil],
      observer_pid: [type: {:or, [:any, nil]}, default: nil],
      timeout: [type: :integer, default: 300_000],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent]
    ]

  alias Jido.Lib.Github.Actions.DocsWriter.Helpers, as: DocsHelpers
  alias Jido.Lib.Github.Helpers
  alias Jido.Lib.Github.Signal.DocsReported

  @max_branch_attempts 8

  @impl true
  def run(params, _context) do
    if params.publish != true do
      with {:ok, local_guide_path} <-
             maybe_write_local_guide(params, params.output_path, params.final_guide) do
        result =
          DocsHelpers.pass_through(params)
          |> Map.put(:published, false)
          |> Map.put(:publish_requested, false)
          |> maybe_put_local_guide_path(local_guide_path)

        emit_docs_signal(result)
        {:ok, result}
      else
        {:error, reason} -> {:error, {:docs_publish_guide_pr_failed, reason}}
      end
    else
      with {:ok, output_path} <- required_output_path(params.output_path),
           {:ok, final_guide} <- validate_final_guide(params.final_guide),
           {:ok, base_branch} <- resolve_base_branch(params),
           :ok <- sync_base_branch(params, base_branch),
           {:ok, branch_name} <- create_branch(params, base_branch),
           :ok <- write_guide(params, output_path, final_guide),
           :ok <- commit_guide(params, output_path),
           {:ok, commit_sha} <- head_sha(params),
           :ok <- push_branch(params, branch_name),
           {:ok, pr} <- ensure_pr(params, branch_name, base_branch, output_path),
           {:ok, local_guide_path} <- maybe_write_local_guide(params, output_path, final_guide) do
        result =
          DocsHelpers.pass_through(params)
          |> Map.put(:publish_requested, true)
          |> Map.put(:published, true)
          |> Map.put(:guide_path, output_path)
          |> Map.put(:base_branch, base_branch)
          |> Map.put(:branch_name, branch_name)
          |> Map.put(:commit_sha, commit_sha)
          |> Map.put(:pr_url, pr[:url])
          |> Map.put(:pr_number, pr[:number])
          |> Map.put(:pr_title, pr[:title])
          |> maybe_put_local_guide_path(local_guide_path)

        emit_docs_signal(result)
        {:ok, result}
      else
        {:error, reason} -> {:error, {:docs_publish_guide_pr_failed, reason}}
      end
    end
  end

  defp required_output_path(path) do
    with {:ok, sanitized} <- DocsHelpers.sanitize_output_path(path),
         true <- is_binary(sanitized) and sanitized != "" do
      {:ok, sanitized}
    else
      false -> {:error, :missing_output_path}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_final_guide(guide) when is_binary(guide) do
    if String.trim(guide) == "" do
      {:error, :empty_final_guide}
    else
      {:ok, guide}
    end
  end

  defp validate_final_guide(_), do: {:error, :missing_final_guide}

  defp maybe_write_local_guide(params, output_path, final_guide) do
    with {:ok, local_output_repo_dir} <-
           normalize_local_output_repo_dir(params[:local_output_repo_dir]),
         {:ok, output_path} <- maybe_require_output_path(output_path, local_output_repo_dir),
         {:ok, final_guide} <- maybe_require_final_guide(final_guide, local_output_repo_dir),
         {:ok, local_guide_path} <- local_guide_path(local_output_repo_dir, output_path),
         :ok <- maybe_write_local_file(local_guide_path, final_guide, local_output_repo_dir) do
      {:ok, local_guide_path}
    end
  end

  defp normalize_local_output_repo_dir(nil), do: {:ok, nil}

  defp normalize_local_output_repo_dir(value) when is_binary(value) do
    case String.trim(value) do
      "" ->
        {:error, :empty_local_output_repo_dir}

      trimmed ->
        expanded = Path.expand(trimmed)

        if File.dir?(expanded) do
          {:ok, expanded}
        else
          {:error, {:local_output_repo_dir_missing, expanded}}
        end
    end
  end

  defp normalize_local_output_repo_dir(_), do: {:error, :invalid_local_output_repo_dir}

  defp maybe_require_output_path(_output_path, nil), do: {:ok, nil}

  defp maybe_require_output_path(output_path, _local_output_repo_dir) do
    required_output_path(output_path)
  end

  defp maybe_require_final_guide(_final_guide, nil), do: {:ok, nil}

  defp maybe_require_final_guide(final_guide, _local_output_repo_dir) do
    validate_final_guide(final_guide)
  end

  defp local_guide_path(nil, _output_path), do: {:ok, nil}

  defp local_guide_path(local_output_repo_dir, output_path)
       when is_binary(local_output_repo_dir) and is_binary(output_path) do
    expanded = Path.expand(output_path, local_output_repo_dir)

    if String.starts_with?(expanded, local_output_repo_dir <> "/") do
      {:ok, expanded}
    else
      {:error, :invalid_local_output_path}
    end
  end

  defp maybe_write_local_file(nil, _final_guide, _local_output_repo_dir), do: :ok

  defp maybe_write_local_file(local_guide_path, final_guide, local_output_repo_dir)
       when is_binary(local_guide_path) and is_binary(final_guide) and
              is_binary(local_output_repo_dir) do
    with :ok <- File.mkdir_p(Path.dirname(local_guide_path)),
         :ok <- File.write(local_guide_path, final_guide) do
      :ok
    else
      {:error, reason} ->
        {:error, {:local_write_failed, local_output_repo_dir, reason}}
    end
  end

  defp maybe_put_local_guide_path(result, nil) when is_map(result), do: result

  defp maybe_put_local_guide_path(result, local_guide_path)
       when is_map(result) and is_binary(local_guide_path) do
    Map.put(result, :local_guide_path, local_guide_path)
  end

  defp resolve_base_branch(params) do
    cmd =
      "gh repo view #{params.owner}/#{params.repo} --json defaultBranchRef -q .defaultBranchRef.name"

    case run_in_repo(params, cmd) do
      {:ok, branch} when is_binary(branch) and branch != "" -> {:ok, branch}
      {:ok, _} -> {:error, :missing_default_branch}
      {:error, reason} -> {:error, reason}
    end
  end

  defp sync_base_branch(params, base_branch) do
    [
      "git fetch origin #{base_branch}",
      "git checkout #{base_branch}",
      "git pull --ff-only origin #{base_branch}"
    ]
    |> Enum.reduce_while(:ok, fn cmd, :ok ->
      case run_in_repo(params, cmd) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {cmd, reason}}}
      end
    end)
  end

  defp create_branch(params, _base_branch) do
    base_name = "#{params.branch_prefix}/#{params.run_id}"
    do_create_branch(params, base_name, 0)
  end

  defp do_create_branch(_params, _base_name, attempt) when attempt >= @max_branch_attempts,
    do: {:error, :branch_name_exhausted}

  defp do_create_branch(params, base_name, attempt) do
    candidate = if(attempt == 0, do: base_name, else: "#{base_name}-#{short_rand()}")

    case run_in_repo(params, "git checkout -b #{candidate}") do
      {:ok, _} -> {:ok, candidate}
      {:error, _reason} -> do_create_branch(params, base_name, attempt + 1)
    end
  end

  defp write_guide(params, output_path, final_guide) do
    escaped_path = Helpers.escape_path(output_path)
    output_dir = Helpers.escape_path(Path.dirname(output_path))

    cmd =
      "mkdir -p #{output_dir} && cat > #{escaped_path} << 'JIDO_DOCS_GUIDE_EOF'\n" <>
        final_guide <> "\nJIDO_DOCS_GUIDE_EOF"

    case run_in_repo(params, cmd) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:write_guide_failed, reason}}
    end
  end

  defp commit_guide(params, output_path) do
    quoted_path = Helpers.shell_escape(output_path)

    cmd =
      "git add #{quoted_path} && git commit -m #{Helpers.shell_escape("docs(guide): add generated guide")}"

    case run_in_repo(params, cmd) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:commit_failed, reason}}
    end
  end

  defp head_sha(params) do
    case run_in_repo(params, "git rev-parse HEAD") do
      {:ok, sha} when is_binary(sha) and sha != "" -> {:ok, sha}
      {:ok, _} -> {:error, :missing_head_sha}
      {:error, reason} -> {:error, reason}
    end
  end

  defp push_branch(params, branch_name) do
    case run_in_repo(params, "git push -u origin #{branch_name}") do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:push_failed, reason}}
    end
  end

  defp ensure_pr(params, branch_name, base_branch, output_path) do
    case find_existing_pr(params, branch_name) do
      {:ok, %{} = existing} ->
        {:ok, existing}

      {:ok, nil} ->
        create_pr(params, branch_name, base_branch, output_path)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp find_existing_pr(params, branch_name) do
    cmd =
      "gh pr list --repo #{params.owner}/#{params.repo} " <>
        "--head #{branch_name} --state open --json number,url,title"

    with {:ok, output} <- run_in_repo(params, cmd),
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

  defp create_pr(params, branch_name, base_branch, output_path) do
    title = "docs: add generated guide (#{params.run_id})"

    body =
      """
      ## Automated Documentation Guide

      - Run ID: #{params.run_id}
      - Output Path: #{output_path}
      - Branch: #{branch_name}
      """
      |> String.trim()

    body_file = "/tmp/jido_docs_pr_body_#{params.run_id}.md"
    escaped_body_file = Helpers.escape_path(body_file)

    write_cmd =
      "cat > #{escaped_body_file} << 'JIDO_DOCS_PR_BODY_EOF'\n#{body}\nJIDO_DOCS_PR_BODY_EOF"

    with {:ok, _} <- run_in_repo(params, write_cmd),
         {:ok, output} <-
           run_in_repo(
             params,
             "gh pr create --repo #{params.owner}/#{params.repo} " <>
               "--base #{base_branch} --head #{branch_name} " <>
               "--title #{Helpers.shell_escape(title)} --body-file #{escaped_body_file}"
           ),
         {:ok, pr} <- resolve_pr_from_output_or_query(params, output, branch_name) do
      {:ok, Map.put_new(pr, :title, title)}
    else
      {:error, reason} -> {:error, {:create_pr_failed, reason}}
    end
  end

  defp resolve_pr_from_output_or_query(params, output, branch_name) do
    case extract_url(output) do
      nil ->
        with {:ok, existing} <- find_existing_pr(params, branch_name),
             %{} = pr <- existing do
          {:ok, pr}
        else
          _ -> {:error, :missing_pr_url}
        end

      url ->
        {:ok, %{url: url, number: extract_number(url), title: nil}}
    end
  end

  defp run_in_repo(params, cmd) do
    Helpers.run_in_dir(
      params[:shell_agent_mod] || Jido.Shell.Agent,
      params.session_id,
      params.repo_dir,
      cmd,
      timeout: params[:timeout] || 300_000
    )
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

  defp short_rand do
    :crypto.strong_rand_bytes(2)
    |> Base.encode16(case: :lower)
  end

  defp emit_docs_signal(%{observer_pid: pid} = result) when is_pid(pid) do
    signal =
      DocsReported.new!(%{
        run_id: result[:run_id],
        writer_provider: result[:writer_provider],
        critic_provider: result[:critic_provider],
        output_repo: "#{result[:owner]}/#{result[:repo]}",
        output_path: result[:output_path],
        status: result[:status] || :completed,
        decision: result[:decision],
        published: result[:published],
        pr_url: result[:pr_url],
        summary:
          "published=#{result[:published] == true} decision=#{result[:decision] || :unknown}"
      })

    send(pid, {:jido_lib_signal, signal})
    :ok
  rescue
    _ -> :ok
  end

  defp emit_docs_signal(_result), do: :ok
end
