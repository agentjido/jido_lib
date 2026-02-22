defmodule Jido.Lib.Github.Actions.Quality.ApplySafeFixes do
  @moduledoc """
  Applies allowlisted safe fixes when explicitly enabled.
  """

  use Jido.Action,
    name: "quality_apply_safe_fixes",
    description: "Apply safe quality autofixes",
    compensation: [max_retries: 0],
    schema: [
      repo_dir: [type: :string, required: true],
      fix_plan: [type: {:list, :map}, default: []],
      mode: [type: :atom, default: :report],
      apply: [type: :boolean, default: false]
    ]

  alias Jido.Lib.Github.Actions.Common.CommandRunner
  alias Jido.Lib.Github.Actions.Common.MutationGuard
  alias Jido.Lib.Github.Actions.Quality.Helpers

  @impl true
  def run(params, _context) do
    if params[:mode] == :safe_fix and MutationGuard.mutation_allowed?(params) do
      results = Enum.map(params[:fix_plan], &apply_fix(&1, params.repo_dir, params))
      {:ok, Helpers.pass_through(params) |> Map.put(:applied_fixes, results)}
    else
      skipped = Enum.map(params[:fix_plan], &Map.put(&1, :status, :skipped))
      {:ok, Helpers.pass_through(params) |> Map.put(:applied_fixes, skipped)}
    end
  end

  defp apply_fix(%{strategy: "format"} = fix, repo_dir, params) do
    case CommandRunner.run_local("mix format", repo_dir: repo_dir, params: params) do
      {:ok, _result} -> Map.merge(fix, %{status: :applied, command: "mix format"})
      {:error, reason} -> Map.merge(fix, %{status: :failed, error: inspect(reason)})
    end
  end

  defp apply_fix(%{strategy: "quality_alias"} = fix, repo_dir, _params) do
    mix_file = Path.join(repo_dir, "mix.exs")

    case File.read(mix_file) do
      {:ok, content} ->
        next =
          if String.contains?(content, "quality:") do
            String.replace(
              content,
              ~r/quality:\s*\[[^\]]*\]/,
              "quality: [\"format\", \"credo --all\", \"dialyzer\"]"
            )
          else
            content
          end

        case File.write(mix_file, next) do
          :ok -> Map.merge(fix, %{status: :applied, file: mix_file})
          {:error, reason} -> Map.merge(fix, %{status: :failed, error: inspect(reason)})
        end

      {:error, reason} ->
        Map.merge(fix, %{status: :failed, error: inspect(reason)})
    end
  end

  defp apply_fix(%{strategy: "doctor_stub"} = fix, repo_dir, _params) do
    doc_file = Path.join(repo_dir, "docs/quality_autofix_stub.md")
    File.mkdir_p!(Path.dirname(doc_file))

    content =
      "# Autofix Stub\n\nThis file was created by quality bot safe-fix mode to satisfy doc stub policy checks.\n"

    case File.write(doc_file, content) do
      :ok -> Map.merge(fix, %{status: :applied, file: doc_file})
      {:error, reason} -> Map.merge(fix, %{status: :failed, error: inspect(reason)})
    end
  end

  defp apply_fix(fix, _repo_dir, _params),
    do: Map.merge(fix, %{status: :skipped, reason: :unsupported_strategy})
end
