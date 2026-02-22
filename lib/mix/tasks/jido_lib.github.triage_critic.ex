defmodule Mix.Tasks.JidoLib.Github.TriageCritic do
  @moduledoc """
  Run dual-role writer/critic issue triage workflow.

  ## Usage

      mix jido_lib.github.triage_critic https://github.com/owner/repo/issues/42

  ## Options

  - `--timeout` - Pipeline timeout in seconds (default: 420)
  - `--writer` - Writer provider: claude | amp | codex | gemini (default: claude)
  - `--critic` - Critic provider: claude | amp | codex | gemini (default: codex)
  - `--max-revisions` - Revision budget (v1 supports 0 or 1; default: 1)
  - `--post-comment` - Post final comment to issue (default: true)
  - `--keep-sprite` - Preserve the sprite after run
  """

  use Mix.Task

  @shortdoc "Run IssueTriageCriticBot"

  alias Jido.Lib.Github.Agents.IssueTriageCriticBot
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
          writer: :string,
          critic: :string,
          max_revisions: :integer,
          post_comment: :boolean,
          keep_sprite: :boolean
        ],
        aliases: [t: :timeout]
      )

    issue_url =
      List.first(args) ||
        Mix.raise("Usage: mix jido_lib.github.triage_critic <github_issue_url>")

    timeout = (opts[:timeout] || 420) * 1_000

    result =
      IssueTriageCriticBot.run_issue(issue_url,
        writer_provider: parse_provider(opts[:writer] || :claude, :writer),
        critic_provider: parse_provider(opts[:critic] || :codex, :critic),
        max_revisions: normalize_max_revisions(opts[:max_revisions] || 1),
        post_comment:
          if(Keyword.has_key?(opts, :post_comment), do: opts[:post_comment], else: true),
        keep_sprite: opts[:keep_sprite] || false,
        timeout: timeout,
        jido: Jido.Default,
        debug: false,
        observer: Mix.shell()
      )

    print_summary(result)
    result
  end

  @doc false
  def parse_provider(provider, role) do
    Helpers.provider_normalize!(provider)
  rescue
    ArgumentError ->
      Mix.raise(
        "Invalid --#{role} #{inspect(provider)}. Allowed: #{Helpers.provider_allowed_string()}"
      )
  end

  @doc false
  def normalize_max_revisions(value) when value in [0, 1], do: value

  def normalize_max_revisions(value) do
    Mix.raise("Invalid --max-revisions #{inspect(value)}. Allowed in v1: 0 or 1")
  end

  defp ensure_jido_started! do
    case Jido.start([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> Mix.raise("Unable to start Jido runtime: #{inspect(reason)}")
    end
  end

  defp print_summary(result) when is_map(result) do
    Mix.shell().info("Status: #{result[:status] || :unknown}")
    Mix.shell().info("Run ID: #{result[:run_id] || "n/a"}")
    Mix.shell().info("Decision: #{result[:decision] || "n/a"}")
    Mix.shell().info("Writer: #{result[:writer_provider] || "n/a"}")
    Mix.shell().info("Critic: #{result[:critic_provider] || "n/a"}")
    Mix.shell().info("Iterations: #{result[:iterations_used] || 0}")

    if result[:comment_url] do
      Mix.shell().info("Comment: #{result.comment_url}")
    end

    if error = result[:error] do
      Mix.shell().error("triage critic failed: #{inspect(error)}")
    end
  end
end
