defmodule Jido.Lib.Bots.Foundation.RunContextTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Bots.Foundation.RunContext

  test "from_issue_url/2 normalizes providers and defaults" do
    assert {:ok, context} =
             RunContext.from_issue_url("https://github.com/agentjido/jido/issues/42",
               writer_provider: "claude",
               critic_provider: :codex,
               max_revisions: 1,
               setup_commands: ["mix deps.get"]
             )

    assert context.owner == "agentjido"
    assert context.repo == "jido"
    assert context.issue_number == 42
    assert context.writer_provider == :claude
    assert context.critic_provider == :codex
    assert context.max_revisions == 1
    assert context.setup_commands == ["mix deps.get"]

    intake = RunContext.to_intake(context)
    assert intake.provider == :claude
    assert intake.writer_provider == :claude
    assert intake.critic_provider == :codex
  end

  test "new/1 rejects unsupported revision budgets" do
    assert {:error, %ArgumentError{}} =
             RunContext.new(%{
               issue_url: "https://github.com/agentjido/jido/issues/42",
               writer_provider: :claude,
               critic_provider: :codex,
               max_revisions: 3
             })
  end
end
