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

  test "writes guide to host-local repo when local_output_repo_dir is configured" do
    local_repo_dir =
      Path.join(System.tmp_dir!(), "jido-local-docs-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(local_repo_dir) end)
    File.mkdir_p!(local_repo_dir)

    params = %{
      publish: false,
      run_id: "run-docs-local-copy",
      owner: "test",
      repo: "repo",
      output_path: "priv/pages/docs/learn/agent-fundamentals.md",
      final_guide: "# Local Guide\n\nBody",
      local_output_repo_dir: local_repo_dir,
      repo_dir: "/work/repo",
      session_id: "sess-123",
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(PublishGuidePr, params, %{})
    assert result.published == false
    assert result.local_guide_path == Path.join(local_repo_dir, params.output_path)
    assert File.read!(result.local_guide_path) == params.final_guide
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
