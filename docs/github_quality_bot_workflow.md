# GitHub Quality Bot Workflow

## What This Bot Does

`Jido.Lib.Github.Agents.QualityBot` evaluates repository quality policy and optionally applies allowlisted safe fixes.

## Canonical API

- `Jido.Lib.Github.Agents.QualityBot.run_target/2`

## Canonical Command

- `mix jido_lib.github.quality <target> --yes`

Default task mode is mutating (`--apply true`); `--yes` is required.

## Pipeline

1. `quality_validate_host_env`
2. `quality_resolve_target`
3. `quality_provision_sprite`
4. `quality_clone_or_attach_repo`
5. `quality_load_policy`
6. `quality_discover_repo_facts`
7. `quality_evaluate_checks`
8. `quality_plan_safe_fixes`
9. `quality_apply_safe_fixes`
10. `quality_run_validation_commands`
11. `quality_publish_quality_report`
12. `quality_teardown_workspace`

## Failure Semantics

- Host env / target / policy load failures stop the workflow.
- Validation command failures return `{:quality_validation_failed, ...}`.
- Report publish failures are captured in outputs and surfaced in result metadata.

## Deterministic Test Paths

- `test/jido_lib/github/agents/quality_bot_test.exs`
- `test/jido_lib/github/agents/quality_bot_run_test.exs`
- `test/jido_lib/github/actions/quality/additional_actions_test.exs`
