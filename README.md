# JidoLib

**Standard Library of Jido Agents, Actions, Sensors, and Signals**

JidoLib provides a collection of reusable, composable components for building CLI agents and automation workflows with Jido. Built on the Jido Agent framework, JidoLib includes agents for common tasks, actions for CLI operations, and utilities for logging, validation, and error handling.

## Features

- **Pre-built Agents** — File operations, testing, documentation generation, and more
- **Composable Actions** — Modular action components for CLI tasks
- **Sensors & Signals** — Event streaming and reactive monitoring
- **Schema Validation** — Zoi-based validation for all data structures
- **Error Handling** — Splode-based error classification
- **Jido Core Integration** — Full integration with `jido ~> 2.0.0-rc.5`

## Installation

Add `jido_lib` to your `mix.exs`:

```elixir
def deps do
  [
    {:jido_lib, "~> 0.1"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## Quick Start

### Basic Agent Usage

```elixir
# Import Jido and JidoLib
use Jido
use Jido.Agent

# Define and run an agent
defmodule MyAgent do
  use Jido.Agent

  defstruct []

  # Define actions...
end

# Execute the agent
case MyAgent.run(%MyAgent{}) do
  {:ok, result} -> IO.inspect(result)
  {:error, reason} -> IO.puts("Error: #{reason}")
end
```

### Error Handling

```elixir
# Use JidoLib.Error for all exceptions
try do
  # your code
rescue
  e in JidoLib.Error.InvalidInputError ->
    IO.puts("Validation failed: #{e.message}")
  e in JidoLib.Error.ExecutionFailureError ->
    IO.puts("Execution failed: #{e.message}")
end
```

### Schemas with Zoi

```elixir
# Define schemas in JidoLib.Schema.*
defmodule JidoLib.Schema.Config do
  @schema Zoi.struct(__MODULE__, %{
    name: Zoi.string(),
    timeout: Zoi.integer() |> Zoi.default(5000)
  })

  @type t :: unquote(Zoi.type_spec(@schema))

  def new(attrs), do: Zoi.parse(@schema, attrs)
end
```

## Modules

### Agents (`JidoLib.Agents.*`)

Pre-built agents for common workflows:

- File operations (read, write, transform)
- Test execution and reporting
- Documentation generation
- More coming soon...

### Actions (`JidoLib.Actions.*`)

Composable action modules for CLI tasks.

### Schemas (`JidoLib.Schema.*`)

Zoi-based schemas for validation and type safety.

### Error (`JidoLib.Error`)

Centralized error handling with Splode:

- `InvalidInputError` — Invalid input parameters
- `ExecutionFailureError` — Runtime execution failures
- `ConfigError` — Configuration issues

## Development

### Setup

```bash
mix setup
```

### Tests

```bash
mix test
```

### Code Quality

Run all quality checks:

```bash
mix quality
```

This runs:
- `mix format` — Code formatting
- `mix credo --strict` — Linting
- `mix dialyzer` — Type checking
- `mix doctor --raise` — Documentation coverage

### Documentation

Generate documentation locally:

```bash
mix docs
```

Full documentation will be available at [HexDocs](https://hexdocs.pm/jido_lib).

## Contributing

We welcome contributions! See [CONTRIBUTING.md](./CONTRIBUTING.md) for guidelines.

For AI assistants working with this codebase, see [usage-rules.md](./usage-rules.md).

## Requirements

- **Elixir** `~> 1.18`
- **Jido** `~> 2.0.0-rc.5`

## License

Apache License 2.0 — See [LICENSE](./LICENSE) file for details.

## Resources

- [Jido Documentation](https://github.com/agentjido/jido)
- [Zoi Schemas](https://github.com/agentjido/zoi)
- [Splode Error Handling](https://github.com/agentjido/splode)
