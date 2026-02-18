defmodule JidoLib do
  @moduledoc """
  Standard library of Jido agents and actions for common development tasks.

  JidoLib provides:

  - **Agents**: Pre-built agents for common workflows (file operations, testing, documentation)
  - **Actions**: Composable action modules for CLI tasks
  - **Utilities**: Helpers for logging, error handling, validation

  ## Installation

  Add to your `mix.exs`:

  ```elixir
  def deps do
    [{:jido_lib, "~> 0.1"}]
  end
  ```

  Then run `mix deps.get`.

  ## Quick Start

  See [README.md](../README.md) for examples and detailed documentation.

  ## Error Handling

  All errors are raised via `JidoLib.Error`:

  ```elixir
  try do
    # your code
  rescue
    e in JidoLib.Error.InvalidInputError -> 
      IO.puts("Validation failed: " <> e.message)
  end
  ```

  ## Documentation

  Full documentation is available at https://hexdocs.pm/jido_lib

  ## Development

  For contributing guidelines, see [CONTRIBUTING.md](../CONTRIBUTING.md).
  For AI assistants working with this codebase, see [usage-rules.md](../usage-rules.md).
  """

  @version "0.1.0"

  @doc """
  Returns the version of JidoLib.
  """
  @spec version() :: String.t()
  def version, do: @version
end
