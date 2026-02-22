# GitHub Release Bot Workflow

## What This Bot Does

`Jido.Lib.Github.Agents.ReleaseBot` orchestrates release planning and publish operations with quality gating.

## Canonical API

- `Jido.Lib.Github.Agents.ReleaseBot.run_repo/2`

## Canonical Command

- `mix jido_lib.github.release <owner/repo> --yes`

Default task mode is mutating (`--publish true --dry-run false`); `--yes` is required.

## Pipeline

1. `release_validate_env`
2. `release_provision_sprite`
3. `release_clone_repo`
4. `release_determine_version_bump`
5. `release_generate_changelog`
6. `release_apply_file_updates`
7. `release_run_quality_gate`
8. `release_run_checks`
9. `release_commit_artifacts`
10. `release_create_tag`
11. `release_push_branch_and_tag`
12. `release_create_github_release`
13. `release_publish_hex`
14. `release_post_summary`
15. `release_teardown_workspace`

## Failure Semantics

- Missing publish credentials fail fast in publish mode.
- Quality gate failures abort before mutating release/publish actions.
- Publish actions are guarded by mutation flags and publish mode checks.

## Deterministic Test Paths

- `test/jido_lib/github/agents/release_bot_test.exs`
- `test/jido_lib/github/agents/release_bot_run_test.exs`
- `test/jido_lib/github/actions/release/additional_actions_test.exs`
