# GitHub Roadmap Bot Workflow

## What This Bot Does

`Jido.Lib.Github.Agents.RoadmapBot` runs dependency-aware roadmap queues from markdown stories and GitHub issue sources.

## Canonical API

- `Jido.Lib.Github.Agents.RoadmapBot.run_plan/2`

## Canonical Command

- `mix jido_lib.github.roadmap <repo_or_path> --yes`

Default task mode is mutating (`--apply true --push true --open-pr true`); `--yes` is required.

## Pipeline

1. `roadmap_validate_env`
2. `roadmap_load_markdown_backlog`
3. `roadmap_load_github_issues`
4. `roadmap_merge_sources`
5. `roadmap_build_dependency_graph`
6. `roadmap_select_work_queue`
7. `roadmap_execute_queue_loop`
8. `roadmap_run_per_item_quality_gate`
9. `roadmap_run_per_item_fix_loop`
10. `roadmap_commit_per_item`
11. `roadmap_push_or_open_pr`
12. `roadmap_emit_report`

## Failure Semantics

- Environment/target validation failures stop the workflow.
- Quality gate failures block mutating apply mode.
- Push/PR actions enforce mutation guard and dependency checks.

## Deterministic Test Paths

- `test/jido_lib/github/agents/roadmap_bot_test.exs`
- `test/jido_lib/github/agents/roadmap_bot_run_test.exs`
- `test/jido_lib/github/actions/roadmap/additional_actions_test.exs`
