defmodule Jido.Lib.Github.Actions.TriageCritic.RunCriticPassTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Actions.TriageCritic.RunCriticPass

  setup do
    Jido.Lib.Test.FakeShellState.reset!()
    :ok
  end

  test "runs critic pass and emits structured critique" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "triage-critic-critic-#{System.unique_integer([:positive])}")

    :ok = File.mkdir_p(tmp_dir)

    params = %{
      iteration: 1,
      run_id: "run-critic",
      session_id: "sess-123",
      repo_dir: tmp_dir,
      issue_number: 42,
      issue_url: "https://github.com/agentjido/jido/issues/42",
      issue_brief: "Brief",
      writer_draft_v1: "Writer draft",
      critic_provider: :claude,
      role_runtime_ready: %{claude: true},
      timeout: 60_000,
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent,
      repo: "jido",
      owner: "agentjido",
      workspace_dir: tmp_dir,
      sprite_config: %{},
      sprites_mod: Sprites
    }

    assert {:ok, result} = Jido.Exec.run(RunCriticPass, params, %{})
    assert is_map(result.critique_v1)
    assert result.critique_v1.verdict in [:accept, :revise, :reject]
    assert result.artifacts.critique_v1.path =~ "critic_report_v1.json"
  end
end
