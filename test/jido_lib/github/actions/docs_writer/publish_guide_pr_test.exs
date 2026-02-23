defmodule Jido.Lib.Github.Actions.DocsWriter.PublishGuidePrTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Actions.DocsWriter.PublishGuidePr

  setup do
    Jido.Lib.Test.FakeShellState.reset!()
    :ok
  end

  test "skips publish flow when publish is false" do
    params = %{
      publish: false,
      run_id: "run-docs-publish",
      owner: "test",
      repo: "repo",
      output_path: "docs/generated/guide.md",
      final_guide: "# Guide",
      repo_dir: "/work/repo",
      session_id: "sess-123",
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(PublishGuidePr, params, %{})
    assert result.published == false
    assert result.publish_requested == false
  end

  test "publishes guide via branch, push, and PR creation" do
    params = %{
      publish: true,
      run_id: "run-docs-publish",
      owner: "test",
      repo: "repo",
      output_path: "docs/generated/guide.md",
      final_guide: "# Generated Guide\n\nHello",
      repo_dir: "/work/repo",
      session_id: "sess-123",
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(PublishGuidePr, params, %{})
    assert result.published == true
    assert is_binary(result.branch_name)
    assert result.commit_sha == "head-sha-123"
    assert result.pr_url =~ "/pull/"
    assert is_integer(result.pr_number)
  end

  test "fails when publish=true and output path is missing" do
    params = %{
      publish: true,
      run_id: "run-docs-publish",
      owner: "test",
      repo: "repo",
      final_guide: "# Guide",
      repo_dir: "/work/repo",
      session_id: "sess-123",
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:error, %Jido.Action.Error.ExecutionFailureError{message: message}} =
             Jido.Exec.run(PublishGuidePr, params, %{})

    assert match?({:docs_publish_guide_pr_failed, _}, message)
  end
end
