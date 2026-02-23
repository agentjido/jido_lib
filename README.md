# Jido.Lib

Standard library modules for the Jido ecosystem, including six canonical GitHub bot workflows:

- Issue Triage Bot
- Documentation Writer Bot
- PR Bot
- Quality Bot
- Release Bot
- Roadmap Bot

## Package Purpose

`jido_lib` owns GitHub-domain workflow orchestration:

- issue triage in Sprite workspaces
- documentation generation via persistent multi-repo sprite context
- provider-swappable coding agent execution (`:claude | :amp | :codex | :gemini`)
- branch/commit/check/push/PR/comment lifecycle for issue-to-PR automation
- policy-driven repository quality evaluation and safe-fix flows
- release orchestration (versioning/changelog/quality gate/publish)
- dependency-aware roadmap queue execution

Lower-level runtime concerns stay in `jido_harness`, `jido_shell`, and `jido_vfs`.

## Canonical APIs

### GitHub PR Bot

- `Jido.Lib.Github.Agents.PrBot.run_issue/2`
- `Jido.Lib.Github.Agents.PrBot.build_intake/2`
- `Jido.Lib.Github.Agents.PrBot.intake_signal/1`

```elixir
Jido.Lib.Github.Agents.PrBot.run_issue(
  "https://github.com/owner/repo/issues/42",
  jido: Jido.Default,
  timeout: 900_000
)
```

### GitHub Issue Triage Bot

- `Jido.Lib.Github.Agents.IssueTriageBot.triage/2`
- `Jido.Lib.Github.Agents.IssueTriageBot.intake_signal/2`

```elixir
Jido.Lib.Github.Agents.IssueTriageBot.triage(
  "https://github.com/owner/repo/issues/42",
  jido: Jido.Default,
  timeout: 600_000
)
```

### GitHub Documentation Writer Bot

- `Jido.Lib.Github.Agents.DocumentationWriterBot.run_brief/2`

```elixir
Jido.Lib.Github.Agents.DocumentationWriterBot.run_brief(
  File.read!("brief.md"),
  repos: ["owner/repo:primary", "owner/context_repo:context"],
  output_repo: "primary",
  sprite_name: "docs-sprite-1",
  jido: Jido.Default
)
```

### GitHub Quality Bot

- `Jido.Lib.Github.Agents.QualityBot.run_target/2`

```elixir
Jido.Lib.Github.Agents.QualityBot.run_target(
  "owner/repo",
  apply: false,
  jido: Jido.Default
)
```

### GitHub Release Bot

- `Jido.Lib.Github.Agents.ReleaseBot.run_repo/2`

```elixir
Jido.Lib.Github.Agents.ReleaseBot.run_repo(
  "owner/repo",
  publish: false,
  jido: Jido.Default
)
```

### GitHub Roadmap Bot

- `Jido.Lib.Github.Agents.RoadmapBot.run_plan/2`

```elixir
Jido.Lib.Github.Agents.RoadmapBot.run_plan(
  "owner/repo",
  apply: false,
  push: false,
  open_pr: false,
  jido: Jido.Default
)
```

## Mix Tasks

```bash
mix jido_lib.github.triage https://github.com/owner/repo/issues/42
mix jido_lib.github.docs path/to/brief.md --repo owner/repo:primary --output-repo primary --sprite-name docs-sprite-1
mix jido_lib.github.pr https://github.com/owner/repo/issues/42
mix jido_lib.github.quality owner/repo --yes
mix jido_lib.github.release owner/repo --yes
mix jido_lib.github.roadmap owner/repo --yes
```

Mutation defaults for the new tasks are intentionally aggressive and require `--yes`:

- `mix jido_lib.github.quality` defaults to `--apply true`
- `mix jido_lib.github.release` defaults to `--publish true --dry-run false`
- `mix jido_lib.github.roadmap` defaults to `--apply true --push true --open-pr true`

To run non-mutating mode without `--yes`, explicitly disable mutation flags:

```bash
mix jido_lib.github.quality owner/repo --apply false
mix jido_lib.github.release owner/repo --publish false
mix jido_lib.github.roadmap owner/repo --apply false --push false --open-pr false
```

## Testing Paths

### 1) Deterministic local test suite

```bash
mix test
mix quality
```

Bot-focused suite:

```bash
mix test test/jido_lib/github/agents test/jido_lib/github/actions test/mix/tasks
```

### 2) Live Issue Triage bot smoke test

```bash
mix jido_lib.github.triage \
  https://github.com/owner/repo/issues/42 \
  --provider claude \
  --timeout 600 \
  --setup-cmd "mix deps.get"
```

### 3) Live PR bot smoke test

For orchestration-only validation (skip project checks):

```bash
mix jido_lib.github.pr \
  https://github.com/owner/repo/issues/42 \
  --provider claude \
  --timeout 600 \
  --setup-cmd "mix deps.get" \
  --check-cmd "true"
```

For full gating with project checks:

```bash
mix jido_lib.github.pr \
  https://github.com/owner/repo/issues/42 \
  --provider claude \
  --timeout 600 \
  --setup-cmd "mix deps.get" \
  --check-cmd "mix test --exclude integration"
```

Note: when `--check-cmd` is omitted, PR bot defaults to `mix test --exclude integration`.

### 4) Live Quality/Release/Roadmap smoke commands

```bash
mix jido_lib.github.quality owner/repo --yes
mix jido_lib.github.release owner/repo --yes
mix jido_lib.github.roadmap owner/repo --yes
```

## Credentials Required for Successful Live Runs

### Core required

- `SPRITES_TOKEN`
- `GH_TOKEN` or `GITHUB_TOKEN`

### Provider-specific required

- `claude`: one of `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY`, `CLAUDE_CODE_API_KEY`
- `amp`: `AMP_API_KEY`
- `codex`: `OPENAI_API_KEY`
- `gemini`: one of `GEMINI_API_KEY`, `GOOGLE_API_KEY`, `GOOGLE_GENAI_USE_VERTEXAI`, `GOOGLE_GENAI_USE_GCA`

### Optional but common

- `ANTHROPIC_BASE_URL` (for Claude-compatible proxy endpoints such as Z.AI)

## Workflow Docs

- `docs/github_issue_triage_workflow.md`
- `docs/github_documentation_writer_workflow.md`
- `docs/github_pr_bot_workflow.md`
- `docs/github_quality_bot_workflow.md`
- `docs/github_release_bot_workflow.md`
- `docs/github_roadmap_bot_workflow.md`

## Development

```bash
mix setup
mix test
mix quality
```
