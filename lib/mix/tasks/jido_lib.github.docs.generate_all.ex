defmodule Mix.Tasks.JidoLib.Github.Docs.GenerateAll do
  @moduledoc """
  Generates documentation for all published content plans in a directory.

  ## Usage

      mix jido_lib.github.docs.generate_all priv/content_plan/docs \\
        --provider claude --output-repo agentjido/agentjido_xyz

  ## Options

  - `--output-repo` - Target repo for generated docs (default: agentjido/agentjido_xyz)
  - `--provider` - LLM provider: claude | amp | codex | gemini (default: claude)
  - `--dry-run` - Skip publication (no branch/commit/PR)
  """

  use Mix.Task

  @shortdoc "Generate docs for all published content plans"

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
          dry_run: :boolean
        ]
      )

    path =
      List.first(args) ||
        Mix.raise("Usage: mix jido_lib.github.docs.generate_all <dir>")

    output_repo = opts[:output_repo] || "agentjido/agentjido_xyz"

    provider =
      Mix.Tasks.JidoLib.Github.Docs.parse_provider(opts[:provider], :writer, :claude)

    publish = opts[:dry_run] != true

    files =
      if File.dir?(path) do
        Path.wildcard(Path.join(path, "**/*.md"))
      else
        [path]
      end

    Mix.shell().info("Found #{length(files)} content plans to process.")

    Enum.each(files, fn file ->
      process_file(file, output_repo, provider, publish)
    end)
  end

  defp process_file(file, output_repo, provider, publish) do
    Mix.shell().info("\n=====================================")
    Mix.shell().info("Processing Plan: #{file}")

    plan = ContentPlan.parse_file!(file)

    if Map.get(plan.metadata, :status) == :published do
      run_plan(file, plan, output_repo, provider, publish)
    else
      Mix.shell().info("Skipping unpublished draft: #{file}")
    end
  end

  defp run_plan(file, plan, output_repo, provider, publish) do
    repos = plan_repos(plan, output_repo)
    output_repo_slug = output_repo_slug(output_repo)
    sprite_name = random_sprite_name()

    result =
      DocumentationWriterBot.run_brief(plan.body,
        content_metadata: plan.metadata,
        prompt_overrides: Map.get(plan.metadata, :prompt_overrides, %{}),
        repos: repos,
        output_repo: output_repo_slug,
        sprite_name: sprite_name,
        publish: publish,
        writer_provider: provider,
        critic_provider: provider,
        jido: Jido.Default,
        debug: false,
        observer: Mix.shell()
      )

    Mix.shell().info("Completed: #{file} -> Status: #{result[:status]}")
  end

  defp plan_repos(plan, output_repo) do
    fm_repos =
      plan.metadata
      |> Map.get(:repos, [])
      |> Enum.map(fn repo ->
        if String.contains?(repo, "/"), do: repo, else: "agentjido/#{repo}:#{repo}"
      end)

    Enum.uniq(fm_repos ++ ["#{output_repo}:output"])
  end

  defp output_repo_slug(output_repo) do
    output_repo
    |> String.split(":")
    |> List.last()
  end

  defp random_sprite_name do
    "docs-#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}"
  end

  defp ensure_jido_started! do
    case Jido.start([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> Mix.raise("Unable to start Jido runtime: #{inspect(reason)}")
    end
  end
end
