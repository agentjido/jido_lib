defmodule Jido.Lib.Github.Actions.Roadmap.EmitRoadmapReport do
  @moduledoc """
  Emits roadmap report artifacts and signal output.
  """

  use Jido.Action,
    name: "roadmap_emit_report",
    description: "Emit roadmap report",
    compensation: [max_retries: 0],
    schema: [
      run_id: [type: :string, required: true],
      repo: [type: :string, required: true],
      provider: [type: :atom, default: :codex],
      queue_results: [type: {:list, :map}, default: []],
      summary: [type: {:or, [:map, nil]}, default: nil],
      state_file: [type: {:or, [:string, nil]}, default: nil],
      observer_pid: [type: {:or, [:any, nil]}, default: nil]
    ]

  alias Jido.Lib.Github.Actions.Roadmap.Helpers
  alias Jido.Lib.Github.Signal.RoadmapReported

  @impl true
  def run(params, _context) do
    report = render_report(params)
    report_file = Path.join(System.tmp_dir!(), "jido-roadmap-report-#{params.run_id}.md")
    :ok = File.write!(report_file, report)

    emit_signal(params[:observer_pid], params)

    {:ok,
     Helpers.pass_through(params)
     |> Map.put(:status, :completed)
     |> Map.put(:report, report)
     |> Map.put(:outputs, %{
       state_file: params[:state_file],
       queue_results: params[:queue_results]
     })
     |> Map.update(:artifacts, [report_file], fn current -> Enum.uniq([report_file | current]) end)}
  end

  defp emit_signal(pid, params) when is_pid(pid) do
    signal =
      RoadmapReported.new!(%{
        run_id: params.run_id,
        provider: params[:provider] || :codex,
        repo: params.repo,
        status: :completed,
        items_selected: length(params[:queue_results] || []),
        summary: summary_text(params[:summary], params[:queue_results])
      })

    send(pid, {:jido_lib_signal, signal})
    :ok
  rescue
    _ -> :ok
  end

  defp emit_signal(_pid, _params), do: :ok

  defp render_report(params) do
    queue_results = params[:queue_results] || []
    summary = params[:summary] || summarize_queue(queue_results)
    queue_lines = render_queue_lines(queue_results)

    """
    # Roadmap Report

    Repo: #{params.repo}
    Run ID: #{params.run_id}

    Summary:
    - total: #{summary[:total] || 0}
    - completed: #{summary[:completed] || 0}
    - planned: #{summary[:planned] || 0}
    - skipped: #{summary[:skipped] || 0}
    - blocked: #{summary[:blocked] || 0}
    - failed: #{summary[:failed] || 0}

    Queue Results:
    #{queue_lines}
    """
    |> String.trim()
  end

  defp render_queue_lines(queue_results) when is_list(queue_results) do
    Enum.map_join(queue_results, "\n", fn result ->
      "- [#{result[:status]}] #{result[:id]} #{result[:title] || ""}"
    end)
  end

  defp summarize_queue(queue_results) do
    %{
      total: length(queue_results),
      completed: Enum.count(queue_results, &(&1[:status] == :completed)),
      planned: Enum.count(queue_results, &(&1[:status] == :planned)),
      skipped: Enum.count(queue_results, &(&1[:status] == :skipped)),
      blocked: Enum.count(queue_results, &(&1[:status] == :blocked)),
      failed: Enum.count(queue_results, &(&1[:status] == :failed))
    }
  end

  defp summary_text(nil, queue_results),
    do: summary_text(summarize_queue(queue_results), queue_results)

  defp summary_text(summary, _queue_results) do
    "completed=#{summary[:completed] || 0} blocked=#{summary[:blocked] || 0} failed=#{summary[:failed] || 0}"
  end
end
