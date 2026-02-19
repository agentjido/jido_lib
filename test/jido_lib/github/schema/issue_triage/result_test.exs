defmodule Jido.Lib.Github.Schema.IssueTriage.ResultTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Github.Schema.IssueTriage.Result

  test "new/1 validates result fields" do
    assert {:ok, result} =
             Result.new(%{
               status: :completed,
               run_id: "abc123",
               owner: "agentjido",
               repo: "jido",
               issue_number: 42,
               investigation: "report",
               investigation_status: :ok,
               comment_posted: true,
               comment_url: "https://github.com/test/repo/issues/42#issuecomment-1",
               sprite_name: "jido-triage-abc123",
               teardown_verified: true,
               teardown_attempts: 1,
               warnings: ["warn"],
               runtime_checks: %{"gh" => true}
             })

    assert result.status == :completed
    assert result.comment_posted == true
    assert result.teardown_verified == true
  end
end
