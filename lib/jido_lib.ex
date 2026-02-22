defmodule Jido.Lib do
  @moduledoc """
  Standard library modules for the Jido ecosystem.

  Canonical GitHub bot APIs under `Jido.Lib.Github.*`:

  - `Jido.Lib.Github.Agents.IssueTriageBot.triage/2`
  - `Jido.Lib.Github.Agents.PrBot.run_issue/2`
  - `Jido.Lib.Github.Agents.QualityBot.run_target/2`
  - `Jido.Lib.Github.Agents.ReleaseBot.run_repo/2`
  - `Jido.Lib.Github.Agents.RoadmapBot.run_plan/2`
  """

  @version "0.1.0"

  @doc "Returns the package version."
  @spec version() :: String.t()
  def version, do: @version
end
