defmodule Jido.Lib.Github.Actions.Quality.PublishQualityReport do
  @moduledoc """
  Builds and optionally publishes a quality report.
  """

  use Jido.Action,
    name: "quality_publish_quality_report",
    description: "Publish quality report",
    compensation: [max_retries: 0],
    schema: [
      run_id: [type: :string, required: true],
      target: [type: :string, required: true],
      findings: [type: {:list, :map}, default: []],
      summary: [type: :map, default: %{}],
      publish_comment: [type: {:or, [:map, nil]}, default: nil],
      observer_pid: [type: {:or, [:any, nil]}, default: nil],
      provider: [type: :atom, default: :codex],
      github_token: [type: {:or, [:string, nil]}, default: nil]
    ]

  alias Jido.Lib.Github.Actions.Common.CommandRunner
  alias Jido.Lib.Github.Actions.Quality.Helpers
  alias Jido.Lib.Github.Signal.QualityReported

  @impl true
  def run(params, _context) do
    report = render_report(params)

    report_file = Path.join(System.tmp_dir!(), "jido-quality-report-#{params.run_id}.md")
    :ok = File.write!(report_file, report)

    publish_result = maybe_publish_comment(params.publish_comment, report, params.github_token)

    Helpers.emit_signal(params[:observer_pid], QualityReported, %{
      run_id: params.run_id,
      provider: params[:provider] || :codex,
      target: params.target,
      status: :completed,
      findings_count: length(params[:findings] || []),
      summary: "failed=#{params.summary[:failed] || 0}"
    })

    {:ok,
     Helpers.pass_through(params)
     |> Map.put(:report, report)
     |> Map.put(:artifacts, [report_file])
     |> Map.put(:outputs, %{publish: publish_result})}
  end

  defp maybe_publish_comment(nil, _report, _token), do: :skipped

  defp maybe_publish_comment(%{} = publish_comment, report, token) do
    repo = publish_comment[:repo] || publish_comment["repo"]
    issue_number = publish_comment[:issue_number] || publish_comment["issue_number"]

    case {repo, issue_number} do
      {repo, issue_number} when is_binary(repo) and is_integer(issue_number) ->
        do_publish_comment(repo, issue_number, report, token)

      _ ->
        {:publish_failed, :invalid_publish_comment}
    end
  end

  defp do_publish_comment(repo, issue_number, report, token) do
    env_export = gh_token_export(token)
    temp_file = Path.join(System.tmp_dir!(), "jido-quality-comment.md")
    File.write!(temp_file, report)
    cmd = env_export <> "gh issue comment #{issue_number} --repo #{repo} --body-file #{temp_file}"

    case CommandRunner.run_local(cmd, repo_dir: ".", params: %{apply: true, mode: :safe_fix}) do
      {:ok, _} -> :published
      {:error, reason} -> {:publish_failed, reason}
    end
  end

  defp gh_token_export(value) when is_binary(value) and value != "",
    do: "export GH_TOKEN=#{value} && "

  defp gh_token_export(_), do: ""

  defp render_report(params) do
    failed = params.summary[:failed] || 0
    passed = params.summary[:passed] || 0
    total = params.summary[:total_rules] || length(params[:findings] || [])

    findings =
      Enum.map_join(params[:findings], "\n", fn finding ->
        "- [#{finding[:status]}] `#{finding[:id]}` #{finding[:description]}"
      end)

    """
    # Quality Report

    Target: #{params.target}
    Run ID: #{params.run_id}

    Summary:
    - total: #{total}
    - passed: #{passed}
    - failed: #{failed}

    Findings:
    #{findings}
    """
    |> String.trim()
  end
end
