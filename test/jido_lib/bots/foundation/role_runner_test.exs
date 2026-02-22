defmodule Jido.Lib.Bots.Foundation.RoleRunnerTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Bots.Foundation.RoleRunner

  setup do
    Jido.Lib.Test.FakeShellState.reset!()
    :ok
  end

  test "runs writer role via harness stream" do
    assert {:ok, result} =
             RoleRunner.run(
               role: :writer,
               provider: :claude,
               session_id: "sess-123",
               repo_dir: "/work/repo",
               run_id: "run-123",
               prompt: "write a response",
               shell_agent_mod: Jido.Lib.Test.FakeShellAgent
             )

    assert result.role == :writer
    assert result.provider == :claude
    assert result.success? == true
    assert is_binary(result.summary)
  end
end
