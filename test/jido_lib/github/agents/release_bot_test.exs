defmodule Jido.Lib.Github.Agents.ReleaseBotTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Github.Agents.ReleaseBot
  alias Runic.Workflow

  test "build_workflow contains release pipeline nodes" do
    workflow = ReleaseBot.build_workflow()
    components = Workflow.components(workflow)

    assert Map.has_key?(components, :validate_release_env)
    assert Map.has_key?(components, :clone_repo)
    assert Map.has_key?(components, :run_quality_gate)
    assert Map.has_key?(components, :run_release_checks)
    assert Map.has_key?(components, :post_release_summary)
    assert Map.has_key?(components, :teardown_workspace)
  end

  test "run/2 fails fast when jido instance is not started" do
    assert {:error, {:jido_not_started, :missing_jido}, _partial} =
             ReleaseBot.run(%{run_id: "run-1", repo: "owner/repo"},
               jido: :missing_jido,
               timeout: 1_000
             )
  end

  test "plugin_specs/0 wires runtime context and observability plugins" do
    plugin_modules = ReleaseBot.plugin_specs() |> Enum.map(& &1.module)

    assert Jido.Lib.Github.Plugins.Observability in plugin_modules
    assert Jido.Lib.Github.Plugins.RuntimeContext in plugin_modules
  end
end
