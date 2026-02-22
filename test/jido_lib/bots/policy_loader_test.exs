defmodule Jido.Lib.Bots.PolicyLoaderTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Bots.PolicyLoader

  test "loads baseline policy with expected rule set" do
    tmp_dir = unique_tmp_dir("policy-loader-baseline")

    assert {:ok, policy} = PolicyLoader.load(tmp_dir)
    assert is_list(policy.rules)
    assert length(policy.rules) >= 10
    assert Enum.any?(policy.rules, &(&1.id == "qa.required.readme"))
    assert policy.baseline == "generic_package_qa_v1"
  end

  test "applies repo override policy when present" do
    tmp_dir = unique_tmp_dir("policy-loader-override")
    override_dir = Path.join(tmp_dir, ".jido")
    :ok = File.mkdir_p(override_dir)

    override = %{
      "validation_commands" => ["mix test"],
      "rules" => [
        %{
          "id" => "qa.custom.local_rule",
          "description" => "custom override rule",
          "severity" => "low",
          "check" => %{"kind" => "file_exists", "path" => "README.md"}
        }
      ]
    }

    :ok =
      File.write(
        Path.join(override_dir, "quality_policy.json"),
        Jason.encode!(override)
      )

    assert {:ok, policy} = PolicyLoader.load(tmp_dir)
    assert policy.validation_commands == ["mix test"]
    assert Enum.any?(policy.rules, &(&1.id == "qa.custom.local_rule"))
  end

  defp unique_tmp_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    :ok = File.mkdir_p(dir)
    dir
  end
end
