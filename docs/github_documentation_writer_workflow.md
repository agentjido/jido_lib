# GitHub Documentation Writer Workflow

## What This Bot Does

`Jido.Lib.Github.Agents.DocumentationWriterBot` runs a persistent Sprite workflow to generate documentation from a large brief and one or more repository contexts.

Core behavior:

1. Validate host/runtime contracts and docs intake payload.
2. Attach to existing Sprite by explicit `sprite_name`, or create it if missing.
3. Prepare GitHub auth in-sprite.
4. Clone or refresh all repository contexts (alias-based layout).
5. Run setup commands in the selected output repo.
6. Validate runtime and bootstrap writer/critic providers.
7. Execute writer/critic loop (one revision max).
8. Finalize guide and persist artifacts.
9. Optionally write file + open PR in output repo.
10. Keep Sprite by default (or teardown when requested).

## Canonical API

- `Jido.Lib.Github.Agents.DocumentationWriterBot.run_brief/2`
- `Jido.Lib.Github.Agents.DocumentationWriterBot.build_intake/2`
- `Jido.Lib.Github.Agents.DocumentationWriterBot.run/2`
- `Jido.Lib.Github.Agents.DocumentationWriterBot.intake_signal/1`

## Canonical Command

```bash
mix jido_lib.github.docs path/to/brief.md \
  --repo owner/repo:primary \
  --repo owner/other_repo:context \
  --output-repo primary \
  --sprite-name docs-sprite-1
```

Optional publish flow:

```bash
mix jido_lib.github.docs path/to/brief.md \
  --repo owner/repo:primary \
  --output-repo primary \
  --sprite-name docs-sprite-1 \
  --output-path docs/generated/guide.md \
  --publish
```

## Intake Rules

- Repo specs: `owner/repo[:alias]`.
- Output repo is required and must match one repo alias or slug.
- `sprite_name` is required and explicit.
- `max_revisions` supports `0` or `1`.
- `publish=true` requires `output_path`.
- `output_path` must be repo-relative and traversal-safe.

## Outputs

Result map includes:

- `final_guide`, `decision`, `iterations_used`
- `repo_contexts`, `output_repo`, `output_path`
- `publish_requested`, `published`
- `branch_name`, `commit_sha`, `pr_url`, `pr_number`
- `artifacts`, `productions`, `facts`, `events`, `failures`, `error`

## Persistence Defaults

- Sprite is preserved by default (`keep_sprite=true`).
- Use `--destroy-sprite` from mix task to teardown at run end.
