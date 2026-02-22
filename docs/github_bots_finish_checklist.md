# GitHub Bots Finish Checklist

## Completion Checklist

- [x] New bot agents implemented (`QualityBot`, `ReleaseBot`, `RoadmapBot`)
- [x] Existing bot agents retained (`IssueTriageBot`, `PrBot`)
- [x] Mix task destructive defaults enabled for quality/release/roadmap
- [x] Mix task `--yes` interlock enforced for destructive defaults
- [x] Agent-level deterministic tests added for quality/release/roadmap
- [x] Action-level direct tests added for untested quality/release/roadmap actions
- [x] Credo issues resolved for new bot/task code paths
- [x] README/API/docs updated to treat all five bots as canonical

## Workflow Node Coverage Matrix

| Bot | Workflow Node | Test Owner |
| --- | --- | --- |
| IssueTriageBot | `validate_host_env` | `test/jido_lib/github/agents/issue_triage_test.exs` |
| IssueTriageBot | `prepare_github_auth` | `test/jido_lib/github/actions/issue_triage/prepare_github_auth_test.exs` |
| IssueTriageBot | `run_coding_agent` | `test/jido_lib/github/actions/issue_triage/run_coding_agent_test.exs` |
| PrBot | `ensure_branch` | `test/jido_lib/github/actions/pr_bot/ensure_branch_test.exs` |
| PrBot | `ensure_commit` | `test/jido_lib/github/actions/pr_bot/ensure_commit_test.exs` |
| PrBot | `create_pull_request` | `test/jido_lib/github/actions/pr_bot/create_pull_request_test.exs` |
| QualityBot | `quality_validate_host_env` | `test/jido_lib/github/actions/quality/additional_actions_test.exs` |
| QualityBot | `quality_resolve_target` | `test/jido_lib/github/actions/quality/additional_actions_test.exs` |
| QualityBot | `quality_provision_sprite` | `test/jido_lib/github/actions/quality/additional_actions_test.exs` |
| QualityBot | `quality_clone_or_attach_repo` | `test/jido_lib/github/actions/quality/additional_actions_test.exs` |
| QualityBot | `quality_load_policy` | `test/jido_lib/github/actions/quality/additional_actions_test.exs` |
| QualityBot | `quality_discover_repo_facts` | `test/jido_lib/github/actions/quality/additional_actions_test.exs` |
| QualityBot | `quality_evaluate_checks` | `test/jido_lib/github/actions/quality/evaluate_checks_test.exs` |
| QualityBot | `quality_plan_safe_fixes` | `test/jido_lib/github/actions/quality/additional_actions_test.exs` |
| QualityBot | `quality_apply_safe_fixes` | `test/jido_lib/github/actions/quality/additional_actions_test.exs` |
| QualityBot | `quality_run_validation_commands` | `test/jido_lib/github/actions/quality/additional_actions_test.exs` |
| QualityBot | `quality_publish_quality_report` | `test/jido_lib/github/actions/quality/additional_actions_test.exs` |
| QualityBot | `quality_teardown_workspace` | `test/jido_lib/github/actions/quality/additional_actions_test.exs` |
| ReleaseBot | `release_validate_env` | `test/jido_lib/github/actions/release/additional_actions_test.exs` |
| ReleaseBot | `release_provision_sprite` | `test/jido_lib/github/actions/release/additional_actions_test.exs` |
| ReleaseBot | `release_clone_repo` | `test/jido_lib/github/actions/release/additional_actions_test.exs` |
| ReleaseBot | `release_determine_version_bump` | `test/jido_lib/github/actions/release/determine_version_bump_test.exs` |
| ReleaseBot | `release_generate_changelog` | `test/jido_lib/github/actions/release/additional_actions_test.exs` |
| ReleaseBot | `release_apply_file_updates` | `test/jido_lib/github/actions/release/additional_actions_test.exs` |
| ReleaseBot | `release_run_quality_gate` | `test/jido_lib/github/actions/release/additional_actions_test.exs` |
| ReleaseBot | `release_run_checks` | `test/jido_lib/github/actions/release/additional_actions_test.exs` |
| ReleaseBot | `release_commit_artifacts` | `test/jido_lib/github/actions/release/additional_actions_test.exs` |
| ReleaseBot | `release_create_tag` | `test/jido_lib/github/actions/release/additional_actions_test.exs` |
| ReleaseBot | `release_push_branch_and_tag` | `test/jido_lib/github/actions/release/additional_actions_test.exs` |
| ReleaseBot | `release_create_github_release` | `test/jido_lib/github/actions/release/additional_actions_test.exs` |
| ReleaseBot | `release_publish_hex` | `test/jido_lib/github/actions/release/additional_actions_test.exs` |
| ReleaseBot | `release_post_summary` | `test/jido_lib/github/actions/release/additional_actions_test.exs` |
| ReleaseBot | `release_teardown_workspace` | `test/jido_lib/github/actions/release/additional_actions_test.exs` |
| RoadmapBot | `roadmap_validate_env` | `test/jido_lib/github/actions/roadmap/additional_actions_test.exs` |
| RoadmapBot | `roadmap_load_markdown_backlog` | `test/jido_lib/github/actions/roadmap/load_markdown_backlog_test.exs` |
| RoadmapBot | `roadmap_load_github_issues` | `test/jido_lib/github/actions/roadmap/additional_actions_test.exs` |
| RoadmapBot | `roadmap_merge_sources` | `test/jido_lib/github/actions/roadmap/additional_actions_test.exs` |
| RoadmapBot | `roadmap_build_dependency_graph` | `test/jido_lib/github/actions/roadmap/additional_actions_test.exs` |
| RoadmapBot | `roadmap_select_work_queue` | `test/jido_lib/github/actions/roadmap/select_work_queue_test.exs` |
| RoadmapBot | `roadmap_execute_queue_loop` | `test/jido_lib/github/actions/roadmap/execute_queue_loop_test.exs` |
| RoadmapBot | `roadmap_run_per_item_quality_gate` | `test/jido_lib/github/actions/roadmap/additional_actions_test.exs` |
| RoadmapBot | `roadmap_run_per_item_fix_loop` | `test/jido_lib/github/actions/roadmap/additional_actions_test.exs` |
| RoadmapBot | `roadmap_commit_per_item` | `test/jido_lib/github/actions/roadmap/additional_actions_test.exs` |
| RoadmapBot | `roadmap_push_or_open_pr` | `test/jido_lib/github/actions/roadmap/additional_actions_test.exs` |
| RoadmapBot | `roadmap_emit_report` | `test/jido_lib/github/actions/roadmap/additional_actions_test.exs` |
