defmodule Jido.Lib.Github.Actions.IssueTriage.PrepareGithubAuthTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Github.Actions.IssueTriage.PrepareGithubAuth

  defmodule MissingTokenShellAgent do
    def run(_session_id, command, _opts) do
      if String.contains?(command, "GH_TOKEN") do
        {:ok, "missing"}
      else
        {:ok, "ok"}
      end
    end
  end

  setup do
    Jido.Lib.Test.FakeShellState.reset!()
    :ok
  end

  test "passes when github token exists and gh auth status succeeds" do
    assert {:ok, result} =
             PrepareGithubAuth.run(
               %{
                 session_id: "sess-123",
                 shell_agent_mod: Jido.Lib.Test.FakeShellAgent
               },
               %{}
             )

    assert result.github_auth_ready == true
    commands = Jido.Lib.Test.FakeShellState.runs() |> Enum.map(&elem(&1, 1))
    assert Enum.any?(commands, &String.contains?(&1, "GH_TOKEN"))
    assert Enum.any?(commands, &String.contains?(&1, "gh auth status"))
  end

  test "fails when token check reports missing" do
    assert {:error, {:prepare_github_auth_failed, :missing_github_token}} =
             PrepareGithubAuth.run(
               %{
                 session_id: "sess-123",
                 shell_agent_mod: MissingTokenShellAgent
               },
               %{}
             )
  end
end
