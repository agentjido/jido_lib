defmodule Jido.Lib.Github.Actions.DocsWriter.ValidateHostEnvTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Actions.DocsWriter.ValidateHostEnv

  setup do
    previous = %{
      "SPRITES_TOKEN" => System.get_env("SPRITES_TOKEN"),
      "GH_TOKEN" => System.get_env("GH_TOKEN"),
      "OPENAI_API_KEY" => System.get_env("OPENAI_API_KEY"),
      "ANTHROPIC_AUTH_TOKEN" => System.get_env("ANTHROPIC_AUTH_TOKEN")
    }

    System.put_env("SPRITES_TOKEN", "spr-token")
    System.put_env("GH_TOKEN", "gh-token")
    System.put_env("OPENAI_API_KEY", "openai-token")
    System.put_env("ANTHROPIC_AUTH_TOKEN", "anthropic-token")

    on_exit(fn ->
      Enum.each(previous, fn {key, value} ->
        if is_nil(value), do: System.delete_env(key), else: System.put_env(key, value)
      end)
    end)

    :ok
  end

  test "validates and normalizes docs writer intake" do
    params = %{
      run_id: "run-docs-1",
      brief: "Write a getting started guide.",
      repos: ["test/repo:primary", "test/ctx_repo:context"],
      output_repo: "primary",
      writer_provider: :codex,
      critic_provider: :claude,
      max_revisions: 1,
      sprite_name: "docs-sprite",
      sprite_config: %{token: "spr-token"}
    }

    assert {:ok, result} = Jido.Exec.run(ValidateHostEnv, params, %{})
    assert result.provider == :codex
    assert result.owner == "test"
    assert result.repo == "repo"
    assert result.output_repo_context.slug == "test/repo"
    assert length(result.repos) == 2
    assert result.workspace_root == "/work/docs/docs-sprite"
  end

  test "fails when publish requested without output_path" do
    params = %{
      run_id: "run-docs-1",
      brief: "Write docs",
      repos: ["test/repo:primary"],
      output_repo: "primary",
      publish: true,
      writer_provider: :codex,
      critic_provider: :claude,
      max_revisions: 1,
      sprite_name: "docs-sprite",
      sprite_config: %{token: "spr-token"}
    }

    assert {:error, %Jido.Action.Error.ExecutionFailureError{message: message}} =
             Jido.Exec.run(ValidateHostEnv, params, %{})

    assert message == {:docs_validate_host_env_failed, :missing_output_path_for_publish}
  end
end
