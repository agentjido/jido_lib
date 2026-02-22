defmodule Jido.Lib.Github.Actions.Release.PostReleaseSummary do
  @moduledoc """
  Emits release summary output and optional signals.
  """

  use Jido.Action,
    name: "release_post_summary",
    description: "Emit release summary",
    compensation: [max_retries: 0],
    schema: [
      run_id: [type: :string, required: true],
      repo: [type: :string, required: true],
      next_version: [type: :string, required: true],
      release_checks: [type: {:or, [{:list, :map}, nil]}, default: nil],
      observer_pid: [type: {:or, [:any, nil]}, default: nil],
      provider: [type: :atom, default: :codex],
      publish: [type: :boolean, default: false]
    ]

  alias Jido.Lib.Github.Actions.Release.Helpers
  alias Jido.Lib.Github.Signal.ReleaseReported

  @impl true
  def run(params, _context) do
    summary =
      "repo=#{params.repo} version=v#{params.next_version} publish=#{params.publish == true}"

    Helpers.pass_through(params)
    |> Map.put(:summary, summary)
    |> Map.put(:outputs, %{release_checks: params[:release_checks] || []})
    |> then(fn output ->
      emit_signal(params[:observer_pid], params, summary)
      {:ok, output}
    end)
  end

  defp emit_signal(pid, params, summary) when is_pid(pid) do
    signal =
      ReleaseReported.new!(%{
        run_id: params.run_id,
        provider: params[:provider] || :codex,
        repo: params.repo,
        status: :completed,
        version: params.next_version,
        summary: summary
      })

    send(pid, {:jido_lib_signal, signal})
    :ok
  rescue
    _ -> :ok
  end

  defp emit_signal(_pid, _params, _summary), do: :ok
end
