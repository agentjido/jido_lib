defmodule Jido.Lib.Github.Actions.DocsWriter.RunCriticPassTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Actions.DocsWriter.RunCriticPass

  defmodule NoisyCriticShellAgent do
    def run(session_id, command, opts \\ []) do
      if String.contains?(command, "codex exec") do
        {:ok,
         [
           Jason.encode!(%{"type" => "turn.started"}),
           Jason.encode!(%{"type" => "turn.completed", "output_text" => "Looks good"})
         ]
         |> Enum.join("\n")}
      else
        Jido.Lib.Test.FakeShellAgent.run(session_id, command, opts)
      end
    end

    def stop(session_id), do: Jido.Lib.Test.FakeShellAgent.stop(session_id)
  end

  setup do
    Jido.Lib.Test.FakeShellState.reset!()
    :ok
  end

  test "runs critic pass and emits structured critique" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "docs-critic-pass-#{System.unique_integer([:positive])}")

    :ok = File.mkdir_p(tmp_dir)

    params = %{
      iteration: 1,
      run_id: "run-docs-critic",
      session_id: "sess-123",
      repo_dir: tmp_dir,
      docs_brief: "Brief",
      writer_draft_v1: "Draft",
      critic_provider: :codex,
      role_runtime_ready: %{codex: true},
      timeout: 60_000,
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent,
      repo: "repo",
      owner: "test",
      workspace_dir: tmp_dir,
      sprite_config: %{},
      sprites_mod: Sprites
    }

    assert {:ok, result} = Jido.Exec.run(RunCriticPass, params, %{})
    assert is_map(result.critique_v1)
    assert result.critique_v1.verdict in [:accept, :revise, :reject]
    assert result.artifacts.critique_v1.path =~ "critic_report_v1.json"
  end

  test "fails closed when critic output is not parseable JSON critique" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "docs-critic-fail-#{System.unique_integer([:positive])}")

    :ok = File.mkdir_p(tmp_dir)

    params = %{
      iteration: 1,
      run_id: "run-docs-critic-fail",
      session_id: "sess-123",
      repo_dir: tmp_dir,
      docs_brief: "Brief",
      writer_draft_v1: "Draft",
      critic_provider: :codex,
      role_runtime_ready: %{codex: true},
      timeout: 60_000,
      shell_agent_mod: NoisyCriticShellAgent,
      repo: "repo",
      owner: "test",
      workspace_dir: tmp_dir,
      sprite_config: %{},
      sprites_mod: Sprites
    }

    assert {:error, %Jido.Action.Error.ExecutionFailureError{message: message}} =
             Jido.Exec.run(RunCriticPass, params, %{})

    assert message == {:docs_run_critic_pass_failed, :no_critique_payload}
  end
end
