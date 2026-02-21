defmodule Mix.Tasks.JidoLib.Github.Pr do
  @moduledoc """
  Create a pull request from a GitHub issue using the sprite-first PR bot.

  ## Usage

      mix jido_lib.github.pr https://github.com/owner/repo/issues/42

  ## Options

  - `--timeout` - Pipeline timeout in seconds (default: 900)
  - `--keep-sprite` - Preserve the Sprite VM/session after run
  - `--setup-cmd CMD` - Setup command to run in cloned repo (repeatable)
  - `--check-cmd CMD` - Required check command before push/PR (repeatable)
  - `--base-branch BRANCH` - Override detected default base branch
  - `--provider PROVIDER` - Coding provider: claude | amp | codex | gemini
  """

  use Mix.Task

  @shortdoc "Create a PR from a GitHub issue with Jido.Lib"

  alias Jido.Lib.Github.Agents.PrBot
  alias Jido.Lib.Github.Helpers

  @doc false
  def handle_telemetry([:jido_runic, :runnable, status], _measurements, metadata, config) do
    Helpers.handle_telemetry([:jido_runic, :runnable, status], %{}, metadata, config)
  end

  def handle_telemetry([:jido, :runic, :runnable, status], _measurements, metadata, config) do
    Helpers.handle_telemetry([:jido, :runic, :runnable, status], %{}, metadata, config)
  end

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    {:ok, _} = Application.ensure_all_started(:jido)

    case Jido.start([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    {opts, args, _} =
      OptionParser.parse(args,
        strict: [
          timeout: :integer,
          keep_sprite: :boolean,
          setup_cmd: :keep,
          check_cmd: :keep,
          base_branch: :string,
          provider: :string
        ],
        aliases: [t: :timeout, k: :keep_sprite, p: :provider]
      )

    url = List.first(args) || Mix.raise("Usage: mix jido_lib.github.pr <github_issue_url>")
    timeout = (opts[:timeout] || 900) * 1_000
    setup_commands = Keyword.get_values(opts, :setup_cmd)
    check_commands = Keyword.get_values(opts, :check_cmd)
    provider = parse_provider(opts[:provider])

    handler_id = "jido-lib-github-pr-progress-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler_id,
      [
        [:jido_runic, :runnable, :completed],
        [:jido_runic, :runnable, :failed],
        [:jido, :runic, :runnable, :completed],
        [:jido, :runic, :runnable, :failed]
      ],
      &__MODULE__.handle_telemetry/4,
      %{shell: Mix.shell(), start_time: System.monotonic_time(:millisecond)}
    )

    Mix.shell().info("Starting GitHub PR bot...")
    Mix.shell().info("Issue: #{url}")

    result =
      try do
        Helpers.with_logger_level(:warning, fn ->
          result =
            PrBot.run_issue(
              url,
              jido: Jido.Default,
              provider: provider,
              timeout: timeout,
              keep_sprite: opts[:keep_sprite] || false,
              setup_commands: setup_commands,
              check_commands:
                if(check_commands == [],
                  do: ["mix test --exclude integration"],
                  else: check_commands
                ),
              base_branch: opts[:base_branch],
              observer: Mix.shell(),
              debug: false
            )

          print_summary(result)
          result
        end)
      after
        :telemetry.detach(handler_id)
      end

    result
  end

  @doc false
  def parse_issue_url(url), do: PrBot.parse_issue_url(url)

  @doc false
  def build_intake(url, opts), do: PrBot.build_intake(url, opts)

  @doc false
  @spec build_feed_signal(map()) :: Jido.Signal.t()
  def build_feed_signal(payload), do: PrBot.intake_signal(payload)

  defp print_summary(result) when is_map(result) do
    Mix.shell().info("")
    Mix.shell().info("Status: #{result.status}")
    Mix.shell().info("Run ID: #{result.run_id}")

    case result do
      %{status: :completed} ->
        Mix.shell().info("PR: #{result.pr_url || "n/a"}")
        Mix.shell().info("Branch: #{result.branch_name || "n/a"}")

        if result.message do
          Mix.shell().info(result.message)
        end

      %{error: error} when not is_nil(error) ->
        maybe_print_jido_not_started(error)
        Mix.shell().error("pr bot failed: #{inspect(error)}")

      _ ->
        Mix.shell().error("pr bot failed with unknown status")
    end
  end

  defp parse_provider(provider) do
    Helpers.provider_normalize!(provider)
  rescue
    ArgumentError ->
      Mix.raise(
        "Invalid --provider #{inspect(provider)}. Allowed: #{Helpers.provider_allowed_string()}"
      )
  end

  defp maybe_print_jido_not_started({:jido_not_started, jido}) do
    Mix.shell().error(
      "Jido instance #{inspect(jido)} is not started. Start it from your entrypoint before running the bot."
    )
  end

  defp maybe_print_jido_not_started(_), do: :ok
end
