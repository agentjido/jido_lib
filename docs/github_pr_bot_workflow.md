# GitHub PR Bot Workflow

## What This Bot Does

`Jido.Lib.Github.Agents.PrBot` turns a GitHub issue into a pull request in a Sprite:

1. validate host env contract
2. provision sprite session
3. fetch issue context in-sprite
4. clone and set up the target repo
5. validate runtime/tooling/env
6. create a working branch
7. run Claude to implement + commit changes
8. verify commit state and run required checks
9. push branch and create/reuse PR
10. comment issue with PR URL
11. teardown (or preserve) sprite

## Canonical Command

```bash
mix jido_lib.github.pr <github_issue_url>
```

Example:

```bash
mix jido_lib.github.pr https://github.com/agentjido/jido_chat/issues/19
```

## Inputs

Intake payload keys:

- `issue_url` (required)
- `timeout` (default: `900_000`)
- `keep_sprite` (default: `false`)
- `setup_commands` (default: `[]`)
- `check_commands` (default: `["mix test --exclude integration"]`)
- `base_branch` (optional override)
- `branch_prefix` (default: `"jido/prbot"`)

## Outputs

`run_issue/2` returns a map with:

- status/error
- repo/issue identity
- branch + commit metadata
- checks outcome
- PR metadata (`pr_number`, `pr_url`, `pr_title`)
- issue comment outcome
- sprite teardown verification/warnings

## Failure Semantics

Hard gates:

- `ValidateHostEnv`
- `ProvisionSprite`
- `PrepareGithubAuth`
- `FetchIssue`
- `CloneRepo`
- `SetupRepo`
- `ValidateRuntime`
- `EnsureBranch`
- `ClaudeCode`
- `EnsureCommit`
- `RunChecks`
- `PushBranch`
- `CreatePullRequest`

Soft/follow-up behavior:

- `CommentIssueWithPr` failure is captured and returned (non-fatal post-PR).
- `TeardownSprite` uses retry+verify and returns warnings if not verified.
