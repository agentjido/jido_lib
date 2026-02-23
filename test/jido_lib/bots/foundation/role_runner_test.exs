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

  defmodule CodexFallbackShellAgent do
    def run(_session_id, command, _opts \\ []) when is_binary(command) do
      cond do
        String.contains?(command, "cat >") ->
          {:ok, "ok"}

        String.contains?(command, "--full-auto") ->
          {:ok,
           [
             Jason.encode!(%{"type" => "thread.started", "thread_id" => "thread-1"}),
             Jason.encode!(%{"type" => "turn.started"}),
             Jason.encode!(%{
               "type" => "item.completed",
               "item" => %{
                 "type" => "agent_message",
                 "text" =>
                   "I’m blocked from reading the repo: every command fails with a sandbox error (`LandlockRestrict`)."
               }
             }),
             Jason.encode!(%{"type" => "turn.completed", "usage" => %{"output_tokens" => 3}})
           ]
           |> Enum.join("\n")}

        String.contains?(command, "--dangerously-bypass-approvals-and-sandbox") ->
          {:ok,
           [
             Jason.encode!(%{"type" => "thread.started", "thread_id" => "thread-2"}),
             Jason.encode!(%{"type" => "turn.started"}),
             Jason.encode!(%{
               "type" => "item.completed",
               "item" => %{"type" => "agent_message", "text" => "# Resolved guide"}
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

  test "normalizes codex absolute prompt paths into workspace-local prompts" do
    assert {:ok, result} =
             RoleRunner.run(
               role: :writer,
               provider: :codex,
               session_id: "sess-789",
               repo_dir: "/work/repo",
               run_id: "run-abs",
               prompt_file: "/tmp/should-not-be-used.txt",
               prompt: "say hello-world",
               shell_agent_mod: CodexItemShellAgent
             )

    assert result.success? == true
    assert result.prompt_file == ".jido/prompts/jido_writer_prompt_run-abs.txt"
  end

  test "falls back to coding phase when codex triage hits landlock sandbox block" do
    assert {:ok, result} =
             RoleRunner.run(
               role: :writer,
               provider: :codex,
               session_id: "sess-fallback",
               repo_dir: "/work/repo",
               run_id: "run-fallback",
               prompt: "write guide",
               phase: :triage,
               fallback_phase: :coding,
               shell_agent_mod: CodexFallbackShellAgent
             )

    assert result.success? == true
    assert result.summary == "# Resolved guide"
    assert result.phase == :coding
    assert result.fallback_phase == :coding
    assert result.fallback_used? == true
    assert String.contains?(result.command, "--dangerously-bypass-approvals-and-sandbox")
  end
end
