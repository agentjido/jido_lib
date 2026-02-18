# Usage Rules for AI Assistants (Cursor, Claude, etc.)

This document provides guidelines for AI assistants working with the Jido Lib codebase.

## Core Principles

1. **Respect Jido patterns**: Follow the established conventions for agents, actions, and error handling
2. **Preserve module hierarchy**: Keep `JidoLib.Agents.*`, `JidoLib.Actions.*`, `JidoLib.Schema.*` boundaries clear
3. **Schema-first design**: Use Zoi schemas for all data structures
4. **Fail explicitly**: Use `JidoLib.Error` for all error cases

## Structure Overview

```
lib/
├── jido_lib.ex                    # Main module & documentation
├── jido_lib/
│   ├── error.ex                   # Error classification (Splode)
│   ├── agents/                    # Pre-built agents
│   │   ├── file_agent.ex
│   │   ├── test_agent.ex
│   │   └── ...
│   ├── actions/                   # Composable action modules
│   │   ├── file_operations.ex
│   │   └── ...
│   ├── schema/                    # Zoi schemas & structs
│   │   ├── agent_config.ex
│   │   └── ...
│   └── utils/                     # Internal utilities
│       └── ...
test/
├── support/                       # Test fixtures & helpers
└── jido_lib_test.exs
```

## Key Patterns

### Error Handling

Always use `JidoLib.Error` for exceptions:

```elixir
case result do
  :ok -> :ok
  {:error, reason} -> 
    raise JidoLib.Error.validation_error("Message", %{field: reason})
end
```

Never:
```elixir
raise ArgumentError, "..."  # ❌
raise "..."                 # ❌
```

### Schema Validation

Define schemas in `JidoLib.Schema.*` modules using Zoi:

```elixir
defmodule JidoLib.Schema.AgentConfig do
  @schema Zoi.struct(__MODULE__, %{
    name: Zoi.string(),
    timeout: Zoi.integer() |> Zoi.default(5000)
  })

  @type t :: unquote(Zoi.type_spec(@schema))

  def new(attrs), do: Zoi.parse(@schema, attrs)
end
```

### Agent Structure

All agents should:
- Implement the Jido Agent protocol
- Document inputs/outputs in `@moduledoc`
- Use Zoi-validated schemas for inputs
- Emit events through Jido's event system

### Testing

- Test coverage must be ≥90%
- Use fixtures for complex test data
- Place test helpers in `test/support/`
- Name tests descriptively: `test "validates input correctly"`

## Documentation Requirements

Every public module, function, and callback must have:
- `@moduledoc` (with examples for modules)
- `@doc` (with description, parameters, returns)
- `@spec` (type signature)

Example:

```elixir
defmodule JidoLib.Agents.FileAgent do
  @moduledoc """
  Agent for file operations.
  
  Handles reading, writing, and manipulating files safely.
  
  ## Examples
  
      iex> JidoLib.Agents.FileAgent.read_file("/path/to/file")
      {:ok, content}
  """

  @doc """
  Reads a file from disk.
  
  ## Parameters
  
    * `path` - Path to the file to read
    * `opts` - Options keyword list
      * `:encoding` - File encoding (default: "utf-8")
  
  ## Returns
  
    * `{:ok, content}` - File contents as binary
    * `{:error, reason}` - Error if file not found or unreadable
  """
  @spec read_file(String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def read_file(path, opts \\ []) do
    # implementation
  end
end
```

## Code Quality Checklist

Before submitting changes:

- [ ] `mix quality` passes
- [ ] `mix test` passes with >90% coverage
- [ ] `mix doctor --raise` passes (all public APIs documented)
- [ ] No unused variables or imports
- [ ] All exceptions use `JidoLib.Error`
- [ ] All data structures validated via Zoi
- [ ] Conventional commit message format

## Forbidden Patterns

❌ **Do not:**
- Use `nimble_options` (use Zoi instead)
- Use `TypedStruct` (use Zoi pattern instead)
- Raise bare exceptions (use `JidoLib.Error`)
- Create helper functions for deps (use plain deps in mix.exs)
- Add modules without documentation
- Import entire modules (`import Enum` → be specific)
- Use `async: true` in tests without careful consideration

✅ **Do:**
- Use Zoi for schemas
- Use Splode error classification
- Document everything thoroughly
- Write focused, readable tests
- Keep modules under 200 lines when possible

## Adding New Features

1. Create schema in `lib/jido_lib/schema/`
2. Create module in appropriate namespace (`agents/`, `actions/`, etc.)
3. Add comprehensive tests in `test/`
4. Document with examples
5. Update `CHANGELOG.md`
6. Run `mix quality` and ensure all checks pass
7. Commit with conventional message: `feat(scope): description`

## Questions?

Refer to:
- [AGENTS.md](./AGENTS.md) - Project structure
- [CONTRIBUTING.md](./CONTRIBUTING.md) - Development guidelines
- [Jido Documentation](https://github.com/agentjido/jido) - Core concepts
