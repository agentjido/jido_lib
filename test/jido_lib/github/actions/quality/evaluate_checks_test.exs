defmodule Jido.Lib.Github.Actions.Quality.EvaluateChecksTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Bots.PolicyLoader
  alias Jido.Lib.Github.Actions.Quality.{EvaluateChecks, PlanSafeFixes}

  test "evaluates baseline policy rules with deterministic summary counts" do
    repo_dir = build_fixture_repo(include_quality_alias?: true)
    assert {:ok, policy} = PolicyLoader.load(repo_dir)

    params = %{
      repo_dir: repo_dir,
      policy: policy,
      facts: %{},
      mode: :report,
      apply: false
    }

    assert {:ok, result} = Jido.Exec.run(EvaluateChecks, params, %{})
    assert length(result.findings) >= 10
    assert result.summary.total_rules == length(result.findings)
  end

  test "plans safe fixes for autofix-eligible failures" do
    repo_dir = build_fixture_repo(include_quality_alias?: false)
    assert {:ok, policy} = PolicyLoader.load(repo_dir)

    params = %{
      repo_dir: repo_dir,
      policy: policy,
      facts: %{},
      mode: :report,
      apply: false
    }

    assert {:ok, eval_result} = Jido.Exec.run(EvaluateChecks, params, %{})

    assert {:ok, plan_result} =
             Jido.Exec.run(
               PlanSafeFixes,
               %{findings: eval_result.findings, mode: :report, apply: false},
               %{}
             )

    assert Enum.any?(plan_result.fix_plan, &(&1.strategy in ["quality_alias", "doctor_stub"]))
  end

  defp build_fixture_repo(opts) do
    repo_dir =
      Path.join(System.tmp_dir!(), "quality-eval-fixture-#{System.unique_integer([:positive])}")

    :ok = File.mkdir_p(repo_dir)
    :ok = File.mkdir_p(Path.join(repo_dir, ".github/workflows"))

    mix_alias_block =
      if Keyword.get(opts, :include_quality_alias?, true) do
        ~S(quality: ["format", "credo --all", "dialyzer"], setup: ["deps.get"])
      else
        ~S(setup: ["deps.get"])
      end

    mix_exs = """
    defmodule Fixture.MixProject do
      use Mix.Project

      def project do
        [
          app: :fixture,
          version: "0.1.0",
          elixir: "~> 1.18",
          aliases: [#{mix_alias_block}]
        ]
      end
    end
    """

    files = %{
      "README.md" => "# Fixture\n\nDocs are in docs/.\n",
      "CHANGELOG.md" => "# Changelog\n",
      "LICENSE" => "MIT",
      "AGENTS.md" => "# Agents\n",
      ".formatter.exs" =>
        "[inputs: [\"{mix,.formatter}.exs\", \"{config,lib,test}/**/*.{ex,exs}\"]]\n",
      "mix.exs" => mix_exs,
      ".github/workflows/ci.yml" => "name: ci\n",
      ".github/workflows/release.yml" => "name: release\n"
    }

    Enum.each(files, fn {rel, content} ->
      full_path = Path.join(repo_dir, rel)
      :ok = File.mkdir_p(Path.dirname(full_path))
      :ok = File.write(full_path, content)
    end)

    repo_dir
  end
end
