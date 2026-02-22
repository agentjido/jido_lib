defmodule Jido.Lib.Github.Agents.RoadmapBotRunTest do
  use ExUnit.Case, async: false

  alias Jido.Lib.Github.Agents.RoadmapBot

  setup_all do
    {:ok, _} = Application.ensure_all_started(:jido)

    case Jido.start(name: Jido.RoadmapBotRunTest) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    :ok
  end

  test "runs roadmap bot in deterministic dry-run mode" do
    repo_dir = build_repo_fixture("roadmap-bot-run")
    policy_path = write_policy_override(repo_dir)
    run_id = "run-#{System.unique_integer([:positive])}"

    result =
      RoadmapBot.run_plan(repo_dir,
        run_id: run_id,
        provider: :codex,
        stories_dirs: ["specs/stories"],
        apply: false,
        push: false,
        open_pr: false,
        quality_policy_path: policy_path,
        sprite_config: %{token: ""},
        timeout: 90_000,
        jido: Jido.RoadmapBotRunTest,
        debug: false
      )

    assert result.status == :completed
    assert result.bot == :roadmap
    assert is_map(result.outputs)
    assert is_list(result.outputs[:queue_results] || result.outputs["queue_results"])
  end

  test "returns error map for invalid repo target" do
    result =
      RoadmapBot.run_plan("",
        run_id: "run-bad",
        timeout: 30_000,
        jido: Jido.RoadmapBotRunTest,
        debug: false
      )

    assert result.bot == :roadmap
    assert result.status in [:failed, :error]
    refute is_nil(result.error)
  end

  defp build_repo_fixture(prefix) do
    repo_dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    stories_dir = Path.join(repo_dir, "specs/stories")
    :ok = File.mkdir_p(stories_dir)

    :ok =
      File.write(
        Path.join(stories_dir, "core.md"),
        """
        ### ST-CORE-001 First story

        #### Dependencies
        - none

        #### Notes
        initial item

        #### Next
        done
        """
      )

    :ok = File.write(Path.join(repo_dir, "README.md"), "# Repo\n")
    :ok = File.write(Path.join(repo_dir, "mix.exs"), "defmodule Fixture do\nend\n")
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
