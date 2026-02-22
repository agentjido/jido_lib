defmodule Jido.Lib.Github.Actions.Release.AdditionalActionsTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Github.Actions.Release

  test "validate_release_env fails in publish mode without credentials" do
    params = %{
      repo: "owner/repo",
      run_id: "run-1",
      provider: :codex,
      publish: true,
      dry_run: false,
      github_token: nil,
      hex_api_key: nil,
      sprites_token: nil
    }

    assert {:error,
            %Jido.Action.Error.ExecutionFailureError{
              message: {:release_validate_env_failed, :missing_publish_credentials}
            }} =
             Jido.Exec.run(Release.ValidateReleaseEnv, params, %{})
  end

  test "validate_release_env returns warnings in dry-run mode" do
    params = %{
      repo: "owner/repo",
      run_id: "run-1",
      provider: :codex,
      publish: false,
      dry_run: true,
      github_token: nil,
      hex_api_key: nil,
      sprites_token: nil
    }

    assert {:ok, result} = Jido.Exec.run(Release.ValidateReleaseEnv, params, %{})
    assert is_list(result.warnings)
  end

  test "clone_repo attaches local path via target resolver" do
    repo_dir = build_repo_fixture("release-clone")
    params = %{repo: repo_dir, run_id: "run-1", github_token: nil}

    assert {:ok, result} = Jido.Exec.run(Release.CloneRepo, params, %{})
    assert result.repo_dir == Path.expand(repo_dir)
  end

  test "apply_release_file_updates skips writes in dry-run mode" do
    repo_dir = build_repo_fixture("release-apply-skip")

    params = %{
      repo_dir: repo_dir,
      next_version: "0.2.0",
      changelog: "## v0.2.0",
      apply: false,
      publish: false,
      dry_run: true
    }

    assert {:ok, result} = Jido.Exec.run(Release.ApplyReleaseFileUpdates, params, %{})
    assert result.release_plan.updated == false
  end

  test "apply_release_file_updates mutates files when apply is true" do
    repo_dir = build_repo_fixture("release-apply")

    params = %{
      repo_dir: repo_dir,
      next_version: "0.2.0",
      changelog: "## v0.2.0",
      apply: true,
      publish: false,
      dry_run: false
    }

    assert {:ok, result} = Jido.Exec.run(Release.ApplyReleaseFileUpdates, params, %{})
    assert result.release_plan.updated == true

    assert File.read!(Path.join(repo_dir, "mix.exs")) =~ "@version \"0.2.0\""
    assert String.starts_with?(File.read!(Path.join(repo_dir, "CHANGELOG.md")), "## v0.2.0")
  end

  test "generate_changelog emits release section" do
    repo_dir = build_repo_fixture("release-changelog")
    params = %{repo_dir: repo_dir, next_version: "1.0.0"}

    assert {:ok, result} = Jido.Exec.run(Release.GenerateChangelog, params, %{})
    assert result.changelog =~ "## v1.0.0"
  end

  test "run_quality_gate returns error when quality bot cannot complete" do
    params = %{
      repo_dir: "",
      run_id: "run-1",
      provider: :codex,
      quality_policy_path: nil,
      dry_run: true,
      apply: false,
      publish: false
    }

    assert {:error,
            %Jido.Action.Error.ExecutionFailureError{
              message: {:release_quality_gate_failed, %{status: status}}
            }} =
             Jido.Exec.run(Release.RunQualityGate, params, %{})

    assert status in [:failed, :error, :unknown]
  end

  test "run_release_checks executes mix quality command" do
    repo_dir = build_repo_fixture("release-checks")
    params = %{repo_dir: repo_dir, dry_run: true, publish: false}

    assert {:ok, result} = Jido.Exec.run(Release.RunReleaseChecks, params, %{})
    assert [%{status: :ok}] = result.release_checks
  end

  test "commit_release_artifacts skips when publish is false" do
    repo_dir = build_repo_fixture("release-commit-skip")
    params = %{repo_dir: repo_dir, next_version: "0.2.0", publish: false, apply: false}

    assert {:ok, result} = Jido.Exec.run(Release.CommitReleaseArtifacts, params, %{})
    assert "commit skipped: dry-run mode" in result.warnings
  end

  test "create_tag skips when publish is false" do
    params = %{repo_dir: ".", next_version: "0.2.0", publish: false, apply: false}
    assert {:ok, _result} = Jido.Exec.run(Release.CreateTag, params, %{})
  end

  test "push_branch_and_tag skips when publish is false" do
    params = %{repo_dir: ".", next_version: "0.2.0", publish: false, apply: false}
    assert {:ok, _result} = Jido.Exec.run(Release.PushBranchAndTag, params, %{})
  end

  test "create_github_release skips when publish is false" do
    params = %{
      repo: "owner/repo",
      repo_dir: ".",
      next_version: "0.2.0",
      changelog: "## v0.2.0",
      publish: false,
      apply: false,
      github_token: nil
    }

    assert {:ok, _result} = Jido.Exec.run(Release.CreateGithubRelease, params, %{})
  end

  test "publish_hex errors when publish is enabled without hex api key" do
    params = %{repo_dir: ".", publish: true, apply: true, hex_api_key: nil}

    assert {:error,
            %Jido.Action.Error.ExecutionFailureError{
              message: {:release_publish_hex_failed, :missing_hex_api_key}
            }} =
             Jido.Exec.run(Release.PublishHex, params, %{})
  end

  test "publish_hex skips in dry-run mode" do
    params = %{repo_dir: ".", publish: false, apply: false, hex_api_key: nil}
    assert {:ok, _result} = Jido.Exec.run(Release.PublishHex, params, %{})
  end

  test "provision_sprite falls back to local workspace when no token exists" do
    params = %{
      run_id: "run-1",
      repo: "owner/repo",
      timeout: 1_000,
      sprite_config: %{token: ""},
      sprites_token: nil,
      shell_agent_mod: Jido.Lib.Test.FakeShellAgent,
      shell_session_mod: Jido.Lib.Test.FakeShellSession
    }

    assert {:ok, result} = Jido.Exec.run(Release.ProvisionSprite, params, %{})
    assert result.session_id == nil
  end

  test "post_release_summary emits summary and optional signal" do
    params = %{
      run_id: "run-1",
      repo: "owner/repo",
      next_version: "1.0.0",
      release_checks: [%{status: :ok}],
      observer_pid: self(),
      provider: :codex,
      publish: false
    }

    assert {:ok, result} = Jido.Exec.run(Release.PostReleaseSummary, params, %{})
    assert result.summary =~ "version=v1.0.0"

    assert_receive {:jido_lib_signal, %Jido.Signal{type: "jido.lib.github.release.reported"}}
  end

  test "teardown_workspace delegates to quality teardown and succeeds without session" do
    params = %{run_id: "run-1", session_id: nil, shell_agent_mod: Jido.Lib.Test.FakeShellAgent}

    assert {:ok, result} = Jido.Exec.run(Release.TeardownWorkspace, params, %{})
    assert result.teardown_verified == true
  end

  defp build_repo_fixture(prefix) do
    repo_dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    :ok = File.mkdir_p(repo_dir)

    mix_exs = """
    defmodule Fixture.MixProject do
      use Mix.Project
      @version \"0.1.0\"
      def project do
        [
          app: :fixture,
          version: @version,
          elixir: \"~> 1.18\",
          aliases: [quality: ["cmd true"]]
        ]
      end
    end
    """

    :ok = File.write(Path.join(repo_dir, "mix.exs"), mix_exs)
    :ok = File.write(Path.join(repo_dir, "README.md"), "# Repo\n")
    :ok = File.write(Path.join(repo_dir, "CHANGELOG.md"), "# Changelog\n")

    repo_dir
  end
end
