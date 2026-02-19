defmodule Jido.Lib do
  @moduledoc """
  Standard library modules for the Jido ecosystem.

  The current focus is GitHub issue triage under `Jido.Lib.Github.*`,
  with the canonical API at `Jido.Lib.Github.Agents.IssueTriageBot`.
  """

  @version "0.1.0"

  @doc "Returns the package version."
  @spec version() :: String.t()
  def version, do: @version
end
