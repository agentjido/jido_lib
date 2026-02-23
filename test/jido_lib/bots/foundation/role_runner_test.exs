defmodule Jido.Lib.Bots.Foundation.RoleRunnerTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Bots.Foundation.RoleRunner

  defmodule CodexItemShellAgent do
    def run(_session_id, command, _opts \\ []) when is_binary(command) do
      cond do
        String.contains?(command, "cat >") ->
          {:ok, "ok"}

        String.contains?(command, "codex exec") ->
          {:ok,
           [
             Jason.encode!(%{"type" => "thread.started", "thread_id" => "thread-1"}),
             Jason.encode!(%{"type" => "turn.started"}),
             Jason.encode!(%{
               "type" => "item.completed",
               "item" => %{"type" => "agent_message", "text" => "hello-world"}
             }),
             Jason.encode!(%{"type" => "turn.completed", "usage" => %{"output_tokens" => 3}})
           ]
           |> Enum.join("\n")}

        true ->
          {:ok, "ok"}
      end
    end
  end

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

  test "extracts codex final text from item.completed agent_message events" do
    assert {:ok, result} =
             RoleRunner.run(
               role: :writer,
               provider: :codex,
               session_id: "sess-456",
               repo_dir: "/work/repo",
               run_id: "run-456",
               prompt: "say hello-world",
               shell_agent_mod: CodexItemShellAgent
             )

    assert result.success? == true
    assert result.summary == "hello-world"
  end
end
