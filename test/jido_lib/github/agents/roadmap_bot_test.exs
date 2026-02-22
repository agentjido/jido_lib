defmodule Jido.Lib.Github.Agents.RoadmapBotTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Github.Agents.RoadmapBot
  alias Runic.Workflow

  test "build_workflow contains roadmap pipeline nodes" do
    workflow = RoadmapBot.build_workflow()
    components = Workflow.components(workflow)

    assert Map.has_key?(components, :validate_roadmap_env)
    assert Map.has_key?(components, :load_markdown_backlog)
    assert Map.has_key?(components, :select_work_queue)
    assert Map.has_key?(components, :execute_queue_loop)
    assert Map.has_key?(components, :emit_roadmap_report)
  end

  test "run/2 fails fast when jido instance is not started" do
    assert {:error, {:jido_not_started, :missing_jido}, _partial} =
             RoadmapBot.run(%{run_id: "run-1", repo: "owner/repo"},
               jido: :missing_jido,
               timeout: 1_000
             )
  end

  test "plugin_specs/0 wires runtime context and observability plugins" do
    plugin_modules = RoadmapBot.plugin_specs() |> Enum.map(& &1.module)

    assert Jido.Lib.Github.Plugins.Observability in plugin_modules
    assert Jido.Lib.Github.Plugins.RuntimeContext in plugin_modules
  end
end
