defmodule Jido.Lib.Github.Actions.Roadmap.AdditionalActionsTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Github.Actions.Roadmap

  test "validate_roadmap_env wraps invalid target errors" do
    params = %{repo: "", run_id: "run-1", apply: false, push: false, open_pr: false}

    assert {:error,
            %Jido.Action.Error.ExecutionFailureError{
              message: {:roadmap_validate_env_failed, _reason}
            }} =
             Jido.Exec.run(Roadmap.ValidateRoadmapEnv, params, %{})
  end

  test "build_dependency_graph records nodes and edges" do
    merged_items = [
      %{id: "ST-CORE-001", title: "Base", dependencies: []},
      %{id: "ST-CORE-002", title: "Dep", dependencies: ["ST-CORE-001"]}
    ]

    params = %{merged_items: merged_items, auto_include_dependencies: true}

    assert {:ok, result} = Jido.Exec.run(Roadmap.BuildDependencyGraph, params, %{})
    assert map_size(result.dependency_graph.nodes) == 2
    assert {"ST-CORE-002", "ST-CORE-001"} in result.dependency_graph.edges
  end

  test "merge_roadmap_sources deduplicates by id" do
    params = %{
      markdown_items: [%{id: "ST-1", title: "from md"}],
      github_items: [%{id: "ST-1", title: "from gh"}, %{id: "GH-9", title: "issue"}]
    }

    assert {:ok, result} = Jido.Exec.run(Roadmap.MergeRoadmapSources, params, %{})
    assert Enum.map(result.merged_items, & &1.id) == ["ST-1", "GH-9"]
  end

  test "load_github_issues tolerates command failures and returns list" do
    params = %{
      repo: "owner/repo",
      repo_slug: "owner/repo",
      issue_query: "is:open",
      github_token: nil
    }

    assert {:ok, result} = Jido.Exec.run(Roadmap.LoadGithubIssues, params, %{})
    assert is_list(result.github_items)
  end

  test "run_per_item_quality_gate skips when queue is empty" do
    params = %{repo_dir: ".", queue_results: [], apply: false, provider: :codex}

    assert {:ok, result} = Jido.Exec.run(Roadmap.RunPerItemQualityGate, params, %{})
    assert result.quality_gate.status == :skipped
    assert result.quality_gate.passed == true
  end

  test "run_per_item_fix_loop skips when apply is false" do
    params = %{repo_dir: ".", apply: false, provider: :codex}

    assert {:ok, result} = Jido.Exec.run(Roadmap.RunPerItemFixLoop, params, %{})
    assert result.fix_loop.status == :skipped
    assert result.fix_loop.attempts == 0
  end

  test "commit_per_item skips in dry-run mode" do
    params = %{
      repo_dir: ".",
      apply: false,
      queue_results: [%{id: "ST-1", title: "story", status: :completed}]
    }

    assert {:ok, result} = Jido.Exec.run(Roadmap.CommitPerItem, params, %{})
    assert result.committed_items == []
    assert "commit skipped: dry-run mode" in result.warnings
  end

  test "push_or_open_pr skips when push and open_pr are disabled" do
    params = %{repo: "owner/repo", repo_dir: ".", push: false, open_pr: false, apply: false}

    assert {:ok, result} = Jido.Exec.run(Roadmap.PushOrOpenPr, params, %{})
    assert result.push_result == :skipped
    assert result.pr_result == :skipped
  end

  test "push_or_open_pr returns error when open_pr is enabled without push" do
    params = %{repo: "owner/repo", repo_dir: ".", push: false, open_pr: true, apply: true}

    assert {:error,
            %Jido.Action.Error.ExecutionFailureError{
              message: {:roadmap_push_or_open_pr_failed, :open_pr_requires_push}
            }} =
             Jido.Exec.run(Roadmap.PushOrOpenPr, params, %{})
  end

  test "emit_roadmap_report writes markdown artifact" do
    params = %{
      run_id: "run-1",
      repo: "owner/repo",
      provider: :codex,
      queue_results: [%{id: "ST-1", title: "story", status: :planned}],
      summary: %{total: 1, planned: 1, completed: 0, skipped: 0, blocked: 0, failed: 0},
      state_file: "/tmp/roadmap_state.json",
      observer_pid: self()
    }

    assert {:ok, result} = Jido.Exec.run(Roadmap.EmitRoadmapReport, params, %{})
    assert result.status == :completed
    assert Enum.any?(result.artifacts, &String.ends_with?(&1, ".md"))

    assert_receive {:jido_lib_signal, %Jido.Signal{type: "jido.lib.github.roadmap.reported"}}
  end
end
