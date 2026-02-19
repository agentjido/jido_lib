# AGENTS.md — Jido Lib

## Overview

`jido_lib` provides standard-library modules for the Jido ecosystem.

Current focus:
- `Jido.Lib.Github.Agents.IssueTriageBot` (canonical signal-first API + Runic workflow orchestrator)

## Namespace

All GitHub triage code lives under:
- `Jido.Lib.Github.Agents.*`
- `Jido.Lib.Github.Actions.*`
- `Jido.Lib.Github.Schema.*`

Do not introduce generic shell abstractions in this package (for example `Jido.Lib.Shell.Backend`).
Shell backend abstractions belong in `jido_shell`.

## Quality Requirements

- Elixir `~> 1.18`
- Zoi schemas for public structs
- Splode for package-level error classification (`Jido.Lib.Error`)
- `mix quality` and `mix test` must pass before commit
- Public modules/functions must have docs and specs

## Testing Guidance

- Keep unit tests deterministic with fake shell/session modules in `test/support/`
- Keep live Sprite/GitHub tests under `@tag :integration`
- Ensure workflow tests validate node ordering, data pass-through, and teardown behavior

## Workflow Spec

Canonical workflow documentation lives at:
- `docs/github_issue_triage_workflow.md`
