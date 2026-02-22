defmodule Jido.Lib.Github.Actions.Roadmap.ExecuteQueueLoopTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Github.Actions.Roadmap.ExecuteQueueLoop

  test "writes roadmap state file and skips previously completed items on resume" do
    repo_dir = Path.join(System.tmp_dir!(), "roadmap-loop-#{System.unique_integer([:positive])}")
    :ok = File.mkdir_p(repo_dir)

    queue = [
      %{id: "ST-CORE-001", title: "first", dependencies: []}
    ]

    params = %{
      run_id: "run-1",
      repo_dir: repo_dir,
      queue: queue,
      apply: true,
      include_completed: false
    }

    assert {:ok, first_run} = Jido.Exec.run(ExecuteQueueLoop, params, %{})
    assert first_run.state_file =~ ".jido/roadmap_state.json"
    assert [%{status: :completed}] = first_run.queue_results

    assert {:ok, second_run} =
             Jido.Exec.run(ExecuteQueueLoop, Map.put(params, :run_id, "run-2"), %{})

    assert [%{status: :skipped, reason: :already_completed}] = second_run.queue_results
  end
end
