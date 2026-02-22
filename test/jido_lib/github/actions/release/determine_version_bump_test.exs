defmodule Jido.Lib.Github.Actions.Release.DetermineVersionBumpTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Github.Actions.Release.DetermineVersionBump

  test "bumps minor version from mix.exs @version" do
    repo_dir = build_repo("1.2.3")

    params = %{repo_dir: repo_dir, release_type: :minor}
    assert {:ok, result} = Jido.Exec.run(DetermineVersionBump, params, %{})
    assert result.current_version == "1.2.3"
    assert result.next_version == "1.3.0"
    assert result.version_bump == :minor
  end

  test "auto defaults to patch bump" do
    repo_dir = build_repo("2.0.9")

    params = %{repo_dir: repo_dir, release_type: :auto}
    assert {:ok, result} = Jido.Exec.run(DetermineVersionBump, params, %{})
    assert result.next_version == "2.0.10"
    assert result.version_bump == :patch
  end

  defp build_repo(version) do
    repo_dir =
      Path.join(
        System.tmp_dir!(),
        "release-bump-#{version}-#{System.unique_integer([:positive])}"
      )

    :ok = File.mkdir_p(repo_dir)

    :ok =
      File.write(
        Path.join(repo_dir, "mix.exs"),
        """
        defmodule Fixture.MixProject do
          use Mix.Project

          @version "#{version}"

          def project do
            [app: :fixture, version: @version, elixir: "~> 1.18"]
          end
        end
        """
      )

    repo_dir
  end
end
