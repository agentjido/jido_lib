# GitHub Issue Triage Workflow

## What This Bot Does

`Jido.Lib` runs automated GitHub issue triage in a Sprite:

1. validates host env contract
2. starts a sprite session
3. fetches issue context in-sprite
4. clones and prepares the repo in-sprite
5. validates runtime/tooling/env
6. prepares provider runtime (install/auth bootstrap as needed)
7. runs selected coding provider for investigation
8. comments findings on the issue
9. tears down (or preserves) the sprite

The canonical API is `Jido.Lib.Github.Agents.IssueTriageBot.triage/2`.

## Canonical Pipeline

1. `ValidateHostEnv`
2. `ProvisionSprite`
3. `PrepareGithubAuth`
4. `FetchIssue`
5. `CloneRepo`
6. `SetupRepo`
7. `ValidateRuntime`
8. `PrepareProviderRuntime`
9. `RunCodingAgent`
10. `CommentIssue`
11. `TeardownSprite`

## Inputs

The intake signal carries a plain payload map (no public request struct requirement):

- `issue_url`
- `provider` (`:claude | :amp | :codex | :gemini`, default `:claude`)
- `run_id`
- `timeout`
- `keep_sprite`
- `setup_commands`
- `observer_pid` (optional)

The workflow enriches this with parsed and runtime fields (`owner`, `repo`, `issue_number`, `session_id`, `repo_dir`, `runtime_checks`, investigation/comment/teardown fields).

## Outputs

The workflow returns a `Jido.Lib.Github.Schema.IssueTriage.Result` with:

- final status
- investigation details
- comment outcome
- sprite teardown verification/warnings

## Failure Semantics

1. Hard gates (stop forward progress):
   - `ValidateHostEnv`
   - `ProvisionSprite`
   - `PrepareGithubAuth`
   - `FetchIssue`
   - `CloneRepo`
   - `SetupRepo`
   - `ValidateRuntime`
   - `PrepareProviderRuntime`
2. `RunCodingAgent` failure is captured and workflow continues to comment + teardown.
3. `CommentIssue` failure is captured and workflow continues to teardown.
4. `TeardownSprite` uses retry+verify; non-verified teardown returns warnings.

## Signals

Runtime observability signals:

- `jido.lib.github.coding_agent.*`
- `jido.lib.github.validate_runtime.checked`

## Canonical Command

- `mix jido_lib.github.triage <issue_url> [--provider claude|amp|codex|gemini]`
