defmodule Jido.Lib.Bots.PolicyLoader do
  @moduledoc """
  Loads baseline and repo-local quality policies.
  """

  @default_baseline "generic_package_qa_v1"

  @spec load(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def load(repo_dir, opts \\ []) when is_binary(repo_dir) and is_list(opts) do
    baseline = Keyword.get(opts, :baseline, @default_baseline)
    baseline_path = baseline_path(baseline)

    with {:ok, baseline_policy} <- load_json_file(baseline_path),
         {:ok, override_policy} <- load_override_policy(repo_dir, opts) do
      {:ok,
       baseline_policy
       |> deep_merge(override_policy)
       |> Map.put_new("baseline", baseline)
       |> normalize_policy()}
    end
  end

  @spec baseline_path(String.t()) :: String.t()
  def baseline_path(name) when is_binary(name) do
    Path.join([:code.priv_dir(:jido_lib), "policies", "#{name}.json"])
  end

  defp load_override_policy(repo_dir, opts) do
    policy_path =
      Keyword.get(opts, :policy_path) ||
        Path.join([repo_dir, ".jido", "quality_policy.json"])

    case File.read(policy_path) do
      {:ok, content} -> Jason.decode(content)
      {:error, :enoent} -> {:ok, %{}}
      {:error, reason} -> {:error, {:policy_read_failed, policy_path, reason}}
    end
  end

  defp load_json_file(path) when is_binary(path) do
    with {:ok, content} <- File.read(path),
         {:ok, decoded} <- Jason.decode(content),
         true <- is_map(decoded) do
      {:ok, decoded}
    else
      false -> {:error, {:invalid_policy, path}}
      {:error, reason} -> {:error, {:policy_decode_failed, path, reason}}
    end
  end

  defp normalize_policy(policy) when is_map(policy) do
    rules =
      policy
      |> Map.get("rules", [])
      |> Enum.filter(&is_map/1)
      |> Enum.map(&normalize_rule/1)
      |> Enum.reject(&is_nil/1)

    %{
      baseline: normalize_baseline(Map.get(policy, "baseline", @default_baseline)),
      validation_commands: normalize_validation_commands(Map.get(policy, "validation_commands")),
      rules: rules
    }
  end

  defp normalize_rule(rule) when is_map(rule) do
    check = normalize_check(Map.get(rule, "check", %{}))

    %{
      id: normalize_string(Map.get(rule, "id", "")),
      description: normalize_string(Map.get(rule, "description", "")),
      severity: normalize_string(Map.get(rule, "severity", "info")),
      applies_to: normalize_string_list(Map.get(rule, "applies_to", [])),
      check: check,
      autofix: Map.get(rule, "autofix", false) == true,
      autofix_strategy: normalize_nullable_string(Map.get(rule, "autofix_strategy")),
      docs_ref: normalize_nullable_string(Map.get(rule, "docs_ref"))
    }
  rescue
    _ -> nil
  end

  defp normalize_rule(_), do: nil

  defp normalize_check(check) when is_map(check) do
    %{
      kind: normalize_string(Map.get(check, "kind", "command")),
      command: normalize_nullable_string(Map.get(check, "command")),
      path: normalize_nullable_string(Map.get(check, "path")),
      pattern: normalize_nullable_string(Map.get(check, "pattern"))
    }
  end

  defp normalize_check(_), do: %{kind: "command", command: nil, path: nil, pattern: nil}

  defp normalize_validation_commands(cmds) when is_list(cmds) do
    cmds
    |> Enum.filter(&is_binary/1)
    |> case do
      [] -> ["mix quality"]
      valid -> valid
    end
  end

  defp normalize_validation_commands(_), do: ["mix quality"]

  defp normalize_string(value) when is_binary(value), do: value
  defp normalize_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_string(value), do: to_string(value)

  defp normalize_nullable_string(nil), do: nil
  defp normalize_nullable_string(value), do: normalize_string(value)

  defp normalize_string_list(values) when is_list(values) do
    values
    |> Enum.filter(&is_binary/1)
  end

  defp normalize_string_list(_values), do: []

  defp normalize_baseline(value) when is_binary(value) and value != "", do: value
  defp normalize_baseline(_value), do: @default_baseline

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      deep_merge(left_value, right_value)
    end)
  end

  defp deep_merge(_left, right), do: right
end
