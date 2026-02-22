defmodule Jido.Lib.Github.Agents.ReleaseBotRunTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Agents.ReleaseBot

  setup_all do
    {:ok, _} = Application.ensure_all_started(:jido)

    case Jido.start(name: Jido.ReleaseBotRunTest) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    :ok
  end

  setup do
    previous = %{
      "GH_TOKEN" => System.get_env("GH_TOKEN"),
      "GITHUB_TOKEN" => System.get_env("GITHUB_TOKEN"),
      "HEX_API_KEY" => System.get_env("HEX_API_KEY"),
      "SPRITES_TOKEN" => System.get_env("SPRITES_TOKEN")
    }

    on_exit(fn ->
      Enum.each(previous, fn {key, val} ->
        if is_nil(val), do: System.delete_env(key), else: System.put_env(key, val)
      end)
    end)

    :ok
  end

  test "runs release bot end-to-end in dry-run mode" do
    repo_dir = build_repo_fixture("release-bot-run")
    policy_path = write_policy_override(repo_dir)
    run_id = "run-#{System.unique_integer([:positive])}"

    result =
      ReleaseBot.run_repo(repo_dir,
        run_id: run_id,
        provider: :codex,
        publish: false,
        dry_run: true,
        quality_policy_path: policy_path,
        sprite_config: %{token: ""},
        timeout: 90_000,
        jido: Jido.ReleaseBotRunTest,
        debug: false
      )

    assert result.status == :completed
    assert result.bot == :release
    assert is_binary(result.summary)
  end

  test "fails when publish mode is enabled without required credentials" do
    System.delete_env("GH_TOKEN")
    System.delete_env("GITHUB_TOKEN")
    System.delete_env("HEX_API_KEY")
    System.delete_env("SPRITES_TOKEN")

    repo_dir = build_repo_fixture("release-bot-fail")

    result =
      ReleaseBot.run_repo(repo_dir,
        run_id: "run-fail",
        provider: :codex,
        publish: true,
        dry_run: false,
        timeout: 30_000,
        jido: Jido.ReleaseBotRunTest,
        debug: false
      )

    assert result.bot == :release
    assert result.status in [:failed, :error]
    refute is_nil(result.error)
  end

  defp build_repo_fixture(prefix) do
    repo_dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    :ok = File.mkdir_p(Path.join(repo_dir, ".github/workflows"))

    files = %{
      "README.md" => "# Repo\n\nDocs\n",
      "CHANGELOG.md" => "# Changelog\n",
      "LICENSE" => "Apache-2.0\n",
      "AGENTS.md" => "# Agents\n",
      ".formatter.exs" => "[inputs: [\"{mix,.formatter}.exs\"]]\n",
      ".github/workflows/ci.yml" => "name: ci\n",
      ".github/workflows/release.yml" => "name: release\n",
      "mix.exs" => """
      defmodule Fixture.MixProject do
        use Mix.Project
        @version \"0.1.0\"
        def project do
          [
            app: :fixture,
            version: @version,
            elixir: \"~> 1.18\",
            aliases: [setup: [\"deps.get\"], quality: [\"cmd true\"]]
          ]
        end
      end
      """
    }

    Enum.each(files, fn {rel, content} ->
      full = Path.join(repo_dir, rel)
      :ok = File.mkdir_p(Path.dirname(full))
      :ok = File.write(full, content)
    end)

    repo_dir
  end

  defp write_policy_override(repo_dir) do
    policy_dir = Path.join(repo_dir, ".jido")
    policy_path = Path.join(policy_dir, "quality_policy.json")
    :ok = File.mkdir_p(policy_dir)

    policy = %{
      "validation_commands" => ["true"],
      "rules" => []
    }

    :ok = File.write(policy_path, Jason.encode!(policy))
    policy_path
  end
end
