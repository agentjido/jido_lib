defmodule Jido.Lib.Github.Actions.IssueTriage.ExecuteDelegatedRunnableTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Github.Actions.IssueTriage.ExecuteDelegatedRunnable
  alias Jido.Runic.Strategy
  alias Runic.Workflow

  defmodule AddOne do
    use Jido.Action,
      name: "bot2_test_add_one",
      schema: [
        value: [type: :integer, required: true]
      ]

    @impl true
    def run(%{value: value}, _context), do: {:ok, %{value: value + 1}}
  end

  defmodule FailAction do
    use Jido.Action,
      name: "bot2_test_fail",
      schema: [
        value: [type: :integer, required: true]
      ]

    @impl true
    def run(_params, _context), do: {:error, :boom}
  end

  test "executes runnable and emits delegate started/completed signals" do
    runnable =
      build_runnable(AddOne, %{
        value: 3,
        observer_pid: self(),
        run_id: "run-123",
        issue_number: 19,
        session_id: "sess-123"
      })

    assert {:ok, %{}, directives} =
             ExecuteDelegatedRunnable.run(
               %{runnable: runnable, runnable_id: runnable.id, tag: :claude_sprite},
               %{state: %{}}
             )

    assert is_list(directives)

    assert_receive {:jido_lib_signal,
                    %Jido.Signal{
                      type: "jido.lib.github.issue_triage.delegate.started",
                      data: %{run_id: "run-123", issue_number: 19, session_id: "sess-123"}
                    }}

    assert_receive {:jido_lib_signal,
                    %Jido.Signal{
                      type: "jido.lib.github.issue_triage.delegate.completed",
                      data: %{status: :completed}
                    }}
  end

  test "emits delegate failed signal when runnable execution fails" do
    runnable =
      build_runnable(FailAction, %{
        value: 3,
        observer_pid: self(),
        run_id: "run-123",
        issue_number: 19,
        session_id: "sess-123"
      })

    assert {:ok, %{}, _directives} =
             ExecuteDelegatedRunnable.run(
               %{runnable: runnable, runnable_id: runnable.id, tag: :claude_sprite},
               %{state: %{}}
             )

    assert_receive {:jido_lib_signal,
                    %Jido.Signal{
                      type: "jido.lib.github.issue_triage.delegate.failed",
                      data: %{status: :failed, error: error}
                    }}

    assert is_binary(error)
    assert error =~ "boom"
  end

  test "returns error when runnable_id does not match runnable.id" do
    runnable = build_runnable(AddOne, %{value: 1})

    assert {:error, message} =
             ExecuteDelegatedRunnable.run(
               %{runnable: runnable, runnable_id: :wrong_id, tag: :claude_sprite},
               %{state: %{}}
             )

    assert message =~ "Runnable ID mismatch"
  end

  defp build_runnable(action_mod, input) do
    workflow = Workflow.new(name: :execute_delegated_runnable_test) |> Workflow.add(action_mod)
    agent = make_strategy_agent(workflow)

    instruction = %Jido.Instruction{action: :runic_feed_signal, params: %{data: input}}
    {_agent, [directive]} = Strategy.cmd(agent, [instruction], %{strategy_opts: []})
    directive.runnable
  end

  defp make_strategy_agent(workflow) do
    ctx = %{strategy_opts: [workflow: workflow]}

    agent = %Jido.Agent{
      id: "exec-delegated-#{System.unique_integer([:positive])}",
      name: "execute_delegated_test",
      description: "test",
      schema: [],
      state: %{}
    }

    {agent, _} = Strategy.init(agent, ctx)
    agent
  end
end
