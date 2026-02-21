defmodule Jido.Lib.Github.Agents.PrBotTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Github.Agents.PrBot
  alias Runic.Workflow

  test "build_workflow contains provider-neutral coding node and PR nodes" do
    workflow = PrBot.build_workflow()
    components = Workflow.components(workflow)

    assert Map.has_key?(components, :prepare_provider_runtime)
    assert Map.has_key?(components, :run_setup_commands)
    assert Map.has_key?(components, :run_check_commands)
    assert Map.has_key?(components, :ensure_branch)
    assert Map.has_key?(components, :run_coding_agent)
    assert Map.has_key?(components, :ensure_commit)
    assert Map.has_key?(components, :push_branch)
    assert Map.has_key?(components, :create_pull_request)
    assert Map.has_key?(components, :post_issue_comment)

    assert components[:run_coding_agent].action_mod ==
             Jido.Lib.Github.Actions.RunCodingAgent
  end

  test "run/2 fails fast when jido instance is not started" do
    assert {:error, {:jido_not_started, :missing_jido}, _partial} =
             PrBot.run(%{run_id: "run-1"}, jido: :missing_jido, timeout: 1_000)
  end

  test "plugin_specs/0 wires runtime context and observability plugins" do
    plugin_modules = PrBot.plugin_specs() |> Enum.map(& &1.module)

    assert Jido.Lib.Github.Plugins.Observability in plugin_modules
    assert Jido.Lib.Github.Plugins.RuntimeContext in plugin_modules
  end
end
