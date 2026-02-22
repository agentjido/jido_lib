defmodule Jido.Lib.Github.Agents.QualityBotRunTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Agents.QualityBot

  setup_all do
    {:ok, _} = Application.ensure_all_started(:jido)

    case Jido.start(name: Jido.QualityBotRunTest) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    :ok
  end

  test "runs quality bot end-to-end in report mode" do
    repo_dir = build_repo_fixture("quality-bot-run")
    policy_path = write_policy_override(repo_dir)
    run_id = "run-#{System.unique_integer([:positive])}"

    result =
      QualityBot.run_target(repo_dir,
        run_id: run_id,
        provider: :codex,
        policy_path: policy_path,
        apply: false,
        sprite_config: %{token: ""},
        timeout: 60_000,
        jido: Jido.QualityBotRunTest,
        debug: false
      )

    assert result.status == :completed
    assert result.bot == :quality
    assert is_map(result.summary)
    assert result.summary.total_rules == 0
  end

  test "returns error map for invalid target" do
    result =
      QualityBot.run_target("",
        run_id: "run-bad",
        timeout: 30_000,
        jido: Jido.QualityBotRunTest,
        debug: false
      )

    assert result.bot == :quality
    assert result.status in [:failed, :error]
    refute is_nil(result.error)
  end

  defp build_repo_fixture(prefix) do
    repo_dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    :ok = File.mkdir_p(Path.join(repo_dir, ".github/workflows"))

    files = %{
      "README.md" => "# Repo\n\nSee docs.\n",
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
