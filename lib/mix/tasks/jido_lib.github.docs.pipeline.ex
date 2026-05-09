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
      run_plan(file, plan, output_repo, provider, publish, opts)
    else
      Mix.shell().info(
        "Skipping: unrecognized status #{inspect(Map.get(plan.metadata, :status))}"
      )
    end
  end

  defp run_plan(file, plan, output_repo, provider, publish, opts) do
    result =
      DocumentationWriterBot.run_brief(plan.body,
        content_metadata: plan.metadata,
        prompt_overrides: Map.get(plan.metadata, :prompt_overrides, %{}),
        repos: plan_repos(plan, output_repo),
        output_repo: output_repo_slug(output_repo),
        sprite_name: random_sprite_name(),
        publish: publish,
        max_revisions: opts[:max_revisions] || 1,
        writer_provider: provider,
        critic_provider: provider,
        jido: Jido.Default,
        debug: false,
        observer: Mix.shell()
      )

    Mix.shell().info("Completed: #{file} -> Status: #{result[:status]}")
    maybe_log_pr_url(result)
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

  defp maybe_log_pr_url(%{pr_url: pr_url}) when not is_nil(pr_url) do
    Mix.shell().info("PR: #{pr_url}")
  end

  defp maybe_log_pr_url(_result), do: :ok

  defp ensure_jido_started! do
    case Jido.start([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> Mix.raise("Unable to start Jido runtime: #{inspect(reason)}")
    end
  end
end
