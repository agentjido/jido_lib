defmodule Jido.Lib.Github.Agents.QualityBotTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Github.Agents.QualityBot
  alias Runic.Workflow

  test "build_workflow contains quality pipeline nodes" do
    workflow = QualityBot.build_workflow()
    components = Workflow.components(workflow)

    assert Map.has_key?(components, :validate_host_env)
    assert Map.has_key?(components, :resolve_target)
    assert Map.has_key?(components, :load_policy)
    assert Map.has_key?(components, :evaluate_checks)
    assert Map.has_key?(components, :publish_quality_report)
    assert Map.has_key?(components, :teardown_workspace)
  end

  test "run/2 fails fast when jido instance is not started" do
    assert {:error, {:jido_not_started, :missing_jido}, _partial} =
             QualityBot.run(%{run_id: "run-1"}, jido: :missing_jido, timeout: 1_000)
  end

  test "plugin_specs/0 wires runtime context and observability plugins" do
    plugin_modules = QualityBot.plugin_specs() |> Enum.map(& &1.module)

    assert Jido.Lib.Github.Plugins.Observability in plugin_modules
    assert Jido.Lib.Github.Plugins.RuntimeContext in plugin_modules
  end
end
