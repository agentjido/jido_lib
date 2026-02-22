defmodule Jido.Lib.Github.Actions.Quality.AdditionalActionsTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Github.Actions.Quality

  test "validate_host_env accepts supported provider and normalizes github token" do
    params = %{target: ".", run_id: "run-1", provider: :codex, github_token: "gh-123"}

    assert {:ok, result} = Jido.Exec.run(Quality.ValidateHostEnv, params, %{})
    assert result.github_token == "gh-123"
  end

  test "validate_host_env rejects invalid provider" do
    params = %{target: ".", run_id: "run-1", provider: :bogus}

    assert {:error,
            %Jido.Action.Error.ExecutionFailureError{
              message: {:quality_validate_host_env_failed, {:invalid_provider, :bogus}}
            }} =
             Jido.Exec.run(Quality.ValidateHostEnv, params, %{})
  end

  test "resolve_target handles local target paths" do
    repo_dir = build_repo_fixture("quality-resolve")

    params = %{target: repo_dir, run_id: "run-1", provider: :codex}

    assert {:ok, result} = Jido.Exec.run(Quality.ResolveTarget, params, %{})
    assert result.target_info.kind == :local
    assert result.repo_dir == Path.expand(repo_dir)
  end

  test "clone_or_attach_repo uses local repo path when target kind is local" do
    repo_dir = build_repo_fixture("quality-clone-local")

    params = %{
      target_info: %{kind: :local, path: repo_dir},
      github_token: nil,
      timeout: 1_000,
      session_id: nil,
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent
    }

    assert {:ok, result} = Jido.Exec.run(Quality.CloneOrAttachRepo, params, %{})
    assert result.repo_dir == repo_dir
  end

  test "load_policy loads baseline with local override" do
    repo_dir = build_repo_fixture("quality-load-policy")
    policy_path = write_policy_override(repo_dir)

    params = %{repo_dir: repo_dir, baseline: "generic_package_qa_v1", policy_path: policy_path}

    assert {:ok, result} = Jido.Exec.run(Quality.LoadPolicy, params, %{})
    assert result.policy.baseline == "generic_package_qa_v1"
    assert result.policy.rules == []
    assert result.policy.validation_commands == ["true"]
  end

  test "discover_repo_facts captures required files and workflow flags" do
    repo_dir = build_repo_fixture("quality-facts")

    assert {:ok, result} = Jido.Exec.run(Quality.DiscoverRepoFacts, %{repo_dir: repo_dir}, %{})

    assert result.facts.has_mix_project == true
    assert result.facts.has_ci_workflow == true
    assert result.facts.has_release_workflow == true
    assert result.facts.files["README.md"] == true
  end

  test "plan_safe_fixes includes only autofix-eligible failures" do
    findings = [
      %{
        id: "a",
        status: :failed,
        autofix: true,
        autofix_strategy: "doctor_stub",
        severity: "medium"
      },
      %{
        id: "b",
        status: :failed,
        autofix: false,
        autofix_strategy: "doctor_stub",
        severity: "medium"
      },
      %{
        id: "c",
        status: :passed,
        autofix: true,
        autofix_strategy: "doctor_stub",
        severity: "medium"
      }
    ]

    assert {:ok, result} =
             Jido.Exec.run(
               Quality.PlanSafeFixes,
               %{findings: findings, mode: :report, apply: false},
               %{}
             )

    assert result.fix_plan == [%{id: "a", strategy: "doctor_stub", severity: "medium"}]
  end

  test "apply_safe_fixes skips changes in report mode" do
    repo_dir = build_repo_fixture("quality-apply-skip")

    params = %{
      repo_dir: repo_dir,
      mode: :report,
      apply: false,
      fix_plan: [%{id: "qa.required.agents", strategy: "doctor_stub"}]
    }

    assert {:ok, result} = Jido.Exec.run(Quality.ApplySafeFixes, params, %{})
    assert [%{status: :skipped}] = result.applied_fixes
  end

  test "apply_safe_fixes applies doctor_stub in safe_fix mode" do
    repo_dir = build_repo_fixture("quality-apply-stub")

    params = %{
      repo_dir: repo_dir,
      mode: :safe_fix,
      apply: true,
      fix_plan: [%{id: "qa.required.agents", strategy: "doctor_stub"}]
    }

    assert {:ok, result} = Jido.Exec.run(Quality.ApplySafeFixes, params, %{})
    assert [%{status: :applied}] = result.applied_fixes
    assert File.exists?(Path.join(repo_dir, "docs/quality_autofix_stub.md"))
  end

  test "provision_sprite falls back to local workspace when token is blank" do
    repo_dir = build_repo_fixture("quality-provision-local")

    params = %{
      run_id: "run-1",
      target_info: %{kind: :local, path: repo_dir},
      sprite_config: %{token: ""},
      timeout: 1_000,
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent,
      shell_session_mod: Jido.Lib.Test.FakeShellSession
    }

    assert {:ok, result} = Jido.Exec.run(Quality.ProvisionSprite, params, %{})
    assert result.session_id == nil
    assert result.sprite_name == nil
    assert result.workspace_dir == repo_dir
  end

  test "run_validation_commands executes declared commands" do
    repo_dir = build_repo_fixture("quality-validate")

    params = %{
      repo_dir: repo_dir,
      policy: %{validation_commands: ["true"]},
      mode: :report,
      apply: false
    }

    assert {:ok, result} = Jido.Exec.run(Quality.RunValidationCommands, params, %{})
    assert [%{status: :ok}] = result.validation_results
    assert result.status == :completed
  end

  test "publish_quality_report writes artifact and returns publish status" do
    params = %{
      run_id: "run-1",
      target: "owner/repo",
      findings: [%{id: "qa.required.readme", description: "README", status: :passed}],
      summary: %{total_rules: 1, passed: 1, failed: 0},
      publish_comment: nil,
      provider: :codex,
      observer_pid: self()
    }

    assert {:ok, result} = Jido.Exec.run(Quality.PublishQualityReport, params, %{})
    assert is_binary(result.report)
    assert Enum.any?(result.artifacts, &String.ends_with?(&1, ".md"))
    assert result.outputs.publish == :skipped

    assert_receive {:jido_lib_signal, %Jido.Signal{type: "jido.lib.github.quality.reported"}}
  end

  test "teardown_workspace marks teardown verified when no session exists" do
    params = %{run_id: "run-1", session_id: nil, shell_agent_mod: Jido.Lib.Test.FakeShellAgent}

    assert {:ok, result} = Jido.Exec.run(Quality.TeardownWorkspace, params, %{})
    assert result.teardown_verified == true
    assert result.teardown_attempts == 0
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
            aliases: [setup: [\"deps.get\"], quality: [\"run -e 'IO.puts(\"quality\")'\"]]
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
