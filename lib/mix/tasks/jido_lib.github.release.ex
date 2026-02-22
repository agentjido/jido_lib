defmodule Mix.Tasks.JidoLib.Github.Release do
  @moduledoc """
  Run the Release Bot in dry-run mode by default.

  ## Usage

      mix jido_lib.github.release owner/repo
      mix jido_lib.github.release owner/repo --publish --release-type minor
  """

  use Mix.Task

  @shortdoc "Run Release Bot planning or publish flow"

  alias Jido.Lib.Github.Agents.ReleaseBot
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
          release_type: :string,
          publish: :boolean,
          dry_run: :boolean,
          yes: :boolean,
          quality_policy_path: :string,
          github_token: :string,
          hex_api_key: :string,
          sprites_token: :string
        ],
        aliases: [t: :timeout, p: :provider]
      )

    repo = List.first(args) || Mix.raise("Usage: mix jido_lib.github.release <owner/repo>")
    timeout = (opts[:timeout] || 900) * 1_000
    publish = default_true(opts, :publish)
    dry_run = if Keyword.has_key?(opts, :dry_run), do: opts[:dry_run], else: false

    ensure_yes_for_mutation!(
      opts,
      publish,
      "Release bot defaults to --publish true. Pass --yes to proceed or --publish false to run without publishing."
    )

    result =
      ReleaseBot.run_repo(repo,
        timeout: timeout,
        provider: parse_provider(opts[:provider]),
        release_type: parse_release_type(opts[:release_type]),
        publish: publish,
        dry_run: dry_run,
        quality_policy_path: opts[:quality_policy_path],
        github_token: opts[:github_token],
        hex_api_key: opts[:hex_api_key],
        sprites_token: opts[:sprites_token],
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
  def parse_release_type(nil), do: :auto
  def parse_release_type(:patch), do: :patch
  def parse_release_type(:minor), do: :minor
  def parse_release_type(:major), do: :major
  def parse_release_type(:auto), do: :auto
  def parse_release_type("patch"), do: :patch
  def parse_release_type("minor"), do: :minor
  def parse_release_type("major"), do: :major
  def parse_release_type("auto"), do: :auto

  def parse_release_type(value) do
    Mix.raise("Invalid --release-type #{inspect(value)}. Allowed: patch|minor|major|auto")
  end

  defp print_summary(result) when is_map(result) do
    Mix.shell().info("Status: #{result[:status] || :unknown}")
    Mix.shell().info("Bot: #{result[:bot] || :release}")
    Mix.shell().info("Run ID: #{result[:run_id] || "n/a"}")
    Mix.shell().info("Repo: #{result[:repo] || result[:target] || "n/a"}")

    if summary = result[:summary] do
      Mix.shell().info("Summary: #{summary}")
    end

    if result[:error] do
      Mix.shell().error("release bot failed: #{inspect(result[:error])}")
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

  defp ensure_yes_for_mutation!(_opts, _publish, _message), do: :ok
end
