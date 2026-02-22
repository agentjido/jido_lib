defmodule Jido.Lib.Github.Agents.IssueTriageCriticBotTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Github.Agents.IssueTriageCriticBot
  alias Runic.Workflow

  test "build_workflow contains writer/critic delegated nodes" do
    workflow = IssueTriageCriticBot.build_workflow()
    components = Workflow.components(workflow)

    assert Map.has_key?(components, :prepare_role_runtimes)
    assert Map.has_key?(components, :build_issue_brief)
    assert Map.has_key?(components, :run_writer_pass_v1)
    assert Map.has_key?(components, :run_critic_pass_v1)
    assert Map.has_key?(components, :decide_revision_v1)
    assert Map.has_key?(components, :run_writer_pass_v2)
    assert Map.has_key?(components, :run_critic_pass_v2)
    assert Map.has_key?(components, :decide_revision_v2)
    assert Map.has_key?(components, :finalize_comment)

    assert components[:run_writer_pass_v1].executor == {:child, :writer}
    assert components[:run_critic_pass_v1].executor == {:child, :critic}
  end

  test "run/2 fails fast when jido instance is not started" do
    assert {:error, {:jido_not_started, :missing_jido}, _partial} =
             IssueTriageCriticBot.run(%{run_id: "run-1"}, jido: :missing_jido, timeout: 1_000)
  end

  test "plugin_specs/0 wires runtime context and observability plugins" do
    plugin_modules = IssueTriageCriticBot.plugin_specs() |> Enum.map(& &1.module)

    assert Jido.Lib.Github.Plugins.Observability in plugin_modules
    assert Jido.Lib.Github.Plugins.RuntimeContext in plugin_modules
  end
end
