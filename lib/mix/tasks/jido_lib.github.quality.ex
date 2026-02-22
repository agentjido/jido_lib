defmodule Mix.Tasks.JidoLib.Github.Quality do
  @moduledoc """
  Run the policy-driven Quality Bot against a local repo path or owner/repo slug.

  ## Usage

      mix jido_lib.github.quality path/to/repo
      mix jido_lib.github.quality owner/repo --apply
  """

  use Mix.Task

  @shortdoc "Run Quality Bot checks and optional safe fixes"

  alias Jido.Lib.Github.Agents.QualityBot
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
          apply: :boolean,
          yes: :boolean,
          provider: :string,
          baseline: :string,
          policy_path: :string,
          publish_repo: :string,
          publish_issue: :integer
        ],
        aliases: [t: :timeout, p: :provider]
      )

    target = List.first(args) || Mix.raise("Usage: mix jido_lib.github.quality <target>")
    timeout = (opts[:timeout] || 600) * 1_000
    provider = parse_provider(opts[:provider])
    apply? = default_true(opts, :apply)

    ensure_yes_for_mutation!(
      opts,
      apply?,
      "Quality bot defaults to --apply true. Pass --yes to proceed or --no-apply for report-only mode."
    )

    result =
      QualityBot.run_target(target,
        provider: provider,
        timeout: timeout,
        apply: apply?,
        baseline: opts[:baseline] || "generic_package_qa_v1",
        policy_path: opts[:policy_path],
        publish_comment: build_publish_comment(opts),
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
  def build_publish_comment(opts) when is_list(opts) do
    repo = Keyword.get(opts, :publish_repo)
    issue = Keyword.get(opts, :publish_issue)

    if is_binary(repo) and is_integer(issue) and issue > 0 do
      %{repo: repo, issue_number: issue}
    else
      nil
    end
  end

  defp print_summary(result) when is_map(result) do
    Mix.shell().info("Status: #{result[:status] || :unknown}")
    Mix.shell().info("Bot: #{result[:bot] || :quality}")
    Mix.shell().info("Run ID: #{result[:run_id] || "n/a"}")
    Mix.shell().info("Checks: #{format_summary(result[:summary])}")
    maybe_print_error(result[:error])
  end

  defp ensure_jido_started! do
    case Jido.start([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> Mix.raise("Unable to start Jido runtime: #{inspect(reason)}")
    end
  end

  defp format_summary(nil), do: "total=0 passed=0 failed=0"

  defp format_summary(summary) when is_map(summary) do
    total = summary[:total_rules] || summary["total_rules"] || 0
    passed = summary[:passed] || summary["passed"] || 0
    failed = summary[:failed] || summary["failed"] || 0
    "total=#{total} passed=#{passed} failed=#{failed}"
  end

  defp format_summary(_), do: "total=0 passed=0 failed=0"

  defp maybe_print_error(nil), do: :ok
  defp maybe_print_error(error), do: Mix.shell().error("quality bot failed: #{inspect(error)}")

  defp default_true(opts, key) when is_list(opts) and is_atom(key) do
    if Keyword.has_key?(opts, key), do: opts[key], else: true
  end

  defp ensure_yes_for_mutation!(opts, true, message) do
    if opts[:yes] == true, do: :ok, else: Mix.raise(message)
  end

  defp ensure_yes_for_mutation!(_opts, _apply, _message), do: :ok
end
