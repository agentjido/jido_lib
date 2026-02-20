defmodule Jido.Lib.Github.Actions.IssueTriage.PrepareProviderRuntimeTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Actions.IssueTriage.PrepareProviderRuntime

  setup do
    Jido.Lib.Test.FakeShellState.reset!()
    :ok
  end

  test "bootstraps provider runtime and marks runtime ready" do
    params = %{
      provider: :claude,
      session_id: "sess-123",
      repo_dir: "/work/repo",
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(PrepareProviderRuntime, params, %{})
    assert result.provider_runtime_ready == true
    assert result.provider_bootstrap.provider == :claude
    assert is_list(result.provider_bootstrap.install_results)
    assert is_list(result.provider_bootstrap.auth_bootstrap_results)
  end
end
