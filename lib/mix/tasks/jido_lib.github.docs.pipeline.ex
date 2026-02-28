defmodule Mix.Tasks.JidoLib.Github.Docs.Pipeline do
  @moduledoc """
  Runs the DocumentationWriterBot over a single content plan file.

  ## Usage

      mix jido_lib.github.docs.pipeline path/to/brief.md \\
        --provider claude --output-repo agentjido/agentjido_xyz

  ## Options

  - `--output-repo` - Target repo for generated docs (default: agentjido/agentjido_xyz)
  - `--provider` - LLM provider for writer and critic: claude | amp | codex | gemini (default: claude)
  - `--max-revisions` - Maximum writer/critic revision cycles (default: 3)
  - `--dry-run` - Skip publication (no branch/commit/PR)
  """

  use Mix.Task

  @shortdoc "Run DocumentationWriterBot for a single content plan"

  alias Jido.Lib.Github.Agents.DocumentationWriterBot
  alias Jido.Lib.Github.ContentPlan

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {:ok, _} = Application.ensure_all_started(:jido)
    ensure_jido_started!()

    {opts, args, _} =
      OptionParser.parse(args,
        strict: [
          output_repo: :string,
          provider: :string,
          max_revisions: :integer,
          dry_run: :boolean
        ]
      )

    file =
      List.first(args) ||
        Mix.raise("Usage: mix jido_lib.github.docs.pipeline <file.md>")

    output_repo = opts[:output_repo] || "agentjido/agentjido_xyz"

    provider =
      Mix.Tasks.JidoLib.Github.Docs.parse_provider(opts[:provider], :writer, :claude)

    publish = opts[:dry_run] != true

    Mix.shell().info("\n=====================================")
    Mix.shell().info("Processing Single Plan: #{file}")

    plan = ContentPlan.parse_file!(file)

    if Map.get(plan.metadata, :status) in [:published, :draft] do
      fm_repos =
        Map.get(plan.metadata, :repos, [])
        |> Enum.map(fn r ->
          if String.contains?(r, "/"), do: r, else: "agentjido/#{r}:#{r}"
        end)

      repos = Enum.uniq(fm_repos ++ ["#{output_repo}:output"])

      output_repo_slug =
        output_repo
        |> String.split(":")
        |> List.last()

      sprite_name =
        "docs-#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}"

      max_revisions = opts[:max_revisions] || 1

      result =
        DocumentationWriterBot.run_brief(plan.body,
          content_metadata: plan.metadata,
          prompt_overrides: Map.get(plan.metadata, :prompt_overrides, %{}),
          repos: repos,
          output_repo: output_repo_slug,
          sprite_name: sprite_name,
          publish: publish,
          max_revisions: max_revisions,
          writer_provider: provider,
          critic_provider: provider,
          jido: Jido.Default,
          debug: false,
          observer: Mix.shell()
        )

      Mix.shell().info("Completed: #{file} -> Status: #{result[:status]}")

      if result[:pr_url] do
        Mix.shell().info("PR: #{result[:pr_url]}")
      end
    else
      Mix.shell().info("Skipping: unrecognized status #{inspect(Map.get(plan.metadata, :status))}")
    end
  end

  defp ensure_jido_started! do
    case Jido.start([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> Mix.raise("Unable to start Jido runtime: #{inspect(reason)}")
    end
  end
end
