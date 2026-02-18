# AGENTS.md — Jido Lib

## Overview

Jido Lib is a standard library of reusable agents and actions for common Jido development tasks.

## What This Package Provides

- **Agents**: Pre-built agents for common workflows (file operations, testing, documentation)
- **Actions**: Composable action modules for CLI tasks
- **Utilities**: Helpers for logging, error handling, validation

## AI Agent Instructions

When working with Jido Lib code:

1. **Structure**: Respect the module hierarchy (`JidoLib.Agents.*`, `JidoLib.Actions.*`)
2. **Testing**: All public APIs must have accompanying tests in `test/`
3. **Documentation**: Use `@moduledoc` and `@doc` with examples for all public functions
4. **Error Handling**: Use `JidoLib.Error` module for all exceptions; never raise bare exceptions
5. **Validation**: Use Zoi schemas in modules under `JidoLib.Schema.*`
6. **Commits**: Follow conventional commits format (`feat()`, `fix()`, `docs()`, etc.)

## Quality Standards

- Run `mix quality` before committing
- All modules must pass `doctor --raise`
- Test coverage minimum 90%
- No unused dependencies or variables

## Development Workflow

```bash
# Setup
mix setup

# Test
mix test

# Quality checks
mix quality

# Documentation
mix docs
```

## Dependency on Jido Core

This package depends on `jido ~> 2.0.0-rc.5` for:
- Agent protocol
- Action module system
- Event streaming
- Error classification

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for guidelines.
