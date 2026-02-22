defmodule Jido.Lib.Github.Actions.Release.DetermineVersionBump do
  @moduledoc """
  Determines next semantic version bump from explicit release type.
  """

  use Jido.Action,
    name: "release_determine_version_bump",
    description: "Determine release version bump",
    compensation: [max_retries: 0],
    schema: [
      repo_dir: [type: :string, required: true],
      release_type: [type: :atom, default: :auto]
    ]

  alias Jido.Lib.Github.Actions.Release.Helpers

  @impl true
  def run(params, _context) do
    current = current_version(params.repo_dir)
    bump = normalize_release_type(params[:release_type] || :auto)
    next = bump_version(current, bump)

    {:ok,
     Helpers.pass_through(params)
     |> Map.put(:current_version, current)
     |> Map.put(:version_bump, bump)
     |> Map.put(:next_version, next)}
  end

  defp current_version(repo_dir) do
    mix_file = Path.join(repo_dir, "mix.exs")

    with {:ok, content} <- File.read(mix_file),
         [_, version] <- Regex.run(~r/@version\s+"([0-9]+\.[0-9]+\.[0-9]+)"/, content) do
      version
    else
      _ -> "0.1.0"
    end
  end

  defp normalize_release_type(type) when type in [:patch, :minor, :major], do: type
  defp normalize_release_type(:auto), do: :patch
  defp normalize_release_type("patch"), do: :patch
  defp normalize_release_type("minor"), do: :minor
  defp normalize_release_type("major"), do: :major
  defp normalize_release_type("auto"), do: :patch
  defp normalize_release_type(_), do: :patch

  defp bump_version(version, bump) when is_binary(version) do
    case String.split(version, ".") do
      [maj, min, pat] ->
        {maj, _} = Integer.parse(maj)
        {min, _} = Integer.parse(min)
        {pat, _} = Integer.parse(pat)

        case bump do
          :major -> "#{maj + 1}.0.0"
          :minor -> "#{maj}.#{min + 1}.0"
          _ -> "#{maj}.#{min}.#{pat + 1}"
        end

      _ ->
        "0.1.0"
    end
  end
end
