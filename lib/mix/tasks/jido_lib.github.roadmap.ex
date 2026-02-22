defmodule Mix.Tasks.JidoLib.Github.Roadmap do
  @moduledoc """
  Run the Roadmap Bot using markdown backlog + GitHub issues.

  ## Usage

      mix jido_lib.github.roadmap owner/repo
      mix jido_lib.github.roadmap owner/repo --stories-dir specs/stories --apply --push
  """

  use Mix.Task

  @shortdoc "Run Roadmap Bot execution loop"

  alias Jido.Lib.Github.Agents.RoadmapBot
  alias Jido.Lib.Github.Helpers

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {:ok, _} = Application.ensure_all_started(:jido)
    ensure_jido_started!()

    {opts, args, _} =
      OptionParser.parse(args,
        strict: [
          timeout: :integer,
          provider: :string,
          stories_dir: :keep,
          traceability_file: :string,
          issue_query: :string,
          max_items: :integer,
          start_at: :string,
          end_at: :string,
          only: :string,
          include_completed: :boolean,
          auto_include_dependencies: :boolean,
          apply: :boolean,
          push: :boolean,
          open_pr: :boolean,
          yes: :boolean,
          quality_policy_path: :string
        ],
        aliases: [t: :timeout, p: :provider]
      )

    repo = List.first(args) || Mix.raise("Usage: mix jido_lib.github.roadmap <repo_or_path>")
    timeout = (opts[:timeout] || 900) * 1_000
    apply? = default_true(opts, :apply)
    push? = default_true(opts, :push)
    open_pr? = default_true(opts, :open_pr)
    destructive? = apply? or push? or open_pr?

    ensure_yes_for_mutation!(
      opts,
      destructive?,
      "Roadmap bot defaults to --apply/--push/--open-pr true. Pass --yes to proceed or explicitly disable mutation flags."
    )

    result =
      RoadmapBot.run_plan(repo,
        timeout: timeout,
        provider: parse_provider(opts[:provider]),
        stories_dirs: normalize_stories_dirs(opts),
        traceability_file: opts[:traceability_file],
        issue_query: opts[:issue_query],
        max_items: opts[:max_items],
        start_at: opts[:start_at],
        end_at: opts[:end_at],
        only: opts[:only],
        include_completed: opts[:include_completed] || false,
        auto_include_dependencies:
          if(Keyword.has_key?(opts, :auto_include_dependencies),
            do: opts[:auto_include_dependencies],
            else: true
          ),
        apply: apply?,
        push: push?,
        open_pr: open_pr?,
        quality_policy_path: opts[:quality_policy_path],
        jido: Jido.Default,
        debug: false
      )

    print_summary(result)
    result
  end

  @doc false
  def parse_provider(provider) do
    Helpers.provider_normalize!(provider || :codex)
  rescue
    ArgumentError ->
      Mix.raise(
        "Invalid --provider #{inspect(provider)}. Allowed: #{Helpers.provider_allowed_string()}"
      )
  end

  @doc false
  def normalize_stories_dirs(opts) when is_list(opts) do
    case Keyword.get_values(opts, :stories_dir) do
      [] -> ["specs/stories"]
      values -> values
    end
  end

  defp print_summary(result) when is_map(result) do
    Mix.shell().info("Status: #{result[:status] || :unknown}")
    Mix.shell().info("Bot: #{result[:bot] || :roadmap}")
    Mix.shell().info("Run ID: #{result[:run_id] || "n/a"}")

    if summary = result[:summary] do
      Mix.shell().info("Summary: #{inspect(summary)}")
    end

    if result[:error] do
      Mix.shell().error("roadmap bot failed: #{inspect(result[:error])}")
    end
  end

  defp ensure_jido_started! do
    case Jido.start([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> Mix.raise("Unable to start Jido runtime: #{inspect(reason)}")
    end
  end

  defp default_true(opts, key) when is_list(opts) and is_atom(key) do
    if Keyword.has_key?(opts, key), do: opts[key], else: true
  end

  defp ensure_yes_for_mutation!(opts, true, message) do
    if opts[:yes] == true, do: :ok, else: Mix.raise(message)
  end

  defp ensure_yes_for_mutation!(_opts, _enabled, _message), do: :ok
end
