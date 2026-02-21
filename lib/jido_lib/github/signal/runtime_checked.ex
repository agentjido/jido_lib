defmodule Jido.Lib.Github.Signal.RuntimeChecked do
  @moduledoc """
  Runtime validation signal emitted by GitHub bot runtime checks.
  """

  use Jido.Signal,
    type: "jido.lib.github.validate_runtime.checked",
    default_source: "/github/validate_runtime",
    schema: [
      run_id: [type: :string, required: false],
      issue_number: [type: :integer, required: false],
      session_id: [type: :string, required: false],
      provider: [type: :atom, required: false],
      runtime_checks: [type: :map, required: false]
    ]
end
