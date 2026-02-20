defmodule Mix.Tasks.JidoLib.Github.Triage do
  @moduledoc """
  Triage a GitHub issue using the canonical signal-first GitHub issue bot.

  ## Usage

      mix jido_lib.github.triage https://github.com/owner/repo/issues/42

  ## Options

  - `--timeout` - Pipeline timeout in seconds (default: 300)
  - `--keep-sprite` - Preserve the Sprite VM/session after triage
  - `--setup-cmd CMD` - Setup command to run in the cloned repo (repeatable)
  - `--provider PROVIDER` - Coding provider: claude | amp | codex | gemini
  """

  use Mix.Task

  @shortdoc "Triage a GitHub issue with Jido.Lib"

  alias Jido.Lib.Github.Agents.IssueTriageBot
  alias Jido.Lib.Github.Helpers

  @doc false
  def handle_telemetry([:jido_runic, :runnable, status], _measurements, metadata, config) do
    Helpers.handle_telemetry([:jido_runic, :runnable, status], %{}, metadata, config)
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
        strict: [timeout: :integer, keep_sprite: :boolean, setup_cmd: :keep, provider: :string],
        aliases: [t: :timeout, k: :keep_sprite, p: :provider]
      )

    url = List.first(args) || Mix.raise("Usage: mix jido_lib.github.triage <github_issue_url>")
    timeout = (opts[:timeout] || 300) * 1_000
    provider = parse_provider(opts[:provider])
    setup_commands = setup_commands_from_opts(opts)

    handler_id = "jido-lib-github-triage-progress-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler_id,
      [
        [:jido_runic, :runnable, :completed],
        [:jido_runic, :runnable, :failed]
      ],
      &__MODULE__.handle_telemetry/4,
      %{shell: Mix.shell(), start_time: System.monotonic_time(:millisecond)}
    )

    Mix.shell().info("Starting GitHub issue triage...")
    Mix.shell().info("Issue: #{url}")

    triage =
      try do
        Helpers.with_logger_level(:warning, fn ->
          triage =
            IssueTriageBot.triage(
              url,
              jido: Jido.Default,
              provider: provider,
              timeout: timeout,
              keep_sprite: opts[:keep_sprite] || false,
              setup_commands: setup_commands,
              observer: Mix.shell(),
              debug: false
            )

          print_summary(triage)
          triage
        end)
      after
        :telemetry.detach(handler_id)
      end

    triage
  end

  @doc false
  def parse_issue_url(url), do: IssueTriageBot.parse_issue_url(url)

  @doc false
  def build_intake_attrs(owner, repo, number, url, opts, timeout_ms) do
    IssueTriageBot.build_intake_attrs(owner, repo, number, url,
      provider: parse_provider(Keyword.get(opts, :provider)),
      keep_sprite: opts[:keep_sprite] || false,
      setup_cmd: setup_commands_from_opts(opts),
      timeout: timeout_ms
    )
  end

  @doc false
  @spec build_feed_signal(map()) :: Jido.Signal.t()
  def build_feed_signal(payload) when is_map(payload), do: IssueTriageBot.intake_signal(payload)

  defp print_summary(triage) when is_map(triage) do
    Mix.shell().info("")
    Mix.shell().info("Status: #{triage.status}")
    Mix.shell().info("Productions: #{length(triage.productions)}")
    Mix.shell().info("Facts: #{length(triage.facts)}")
    Mix.shell().info("Events: #{length(triage.events)}")

    case triage do
      %{status: :completed, result: output} when is_map(output) ->
        if is_binary(output.investigation) do
          Mix.shell().info("\n#{output.investigation}\n")
        end

        if output.message do
          Mix.shell().info(output.message)
        end

      %{error: error} when not is_nil(error) ->
        maybe_print_jido_not_started(error)
        Mix.shell().error("triage failed: #{inspect(error)}")

      _ ->
        Mix.shell().error("triage failed with unknown status")
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

  defp setup_commands_from_opts(opts) when is_list(opts) do
    values =
      case Keyword.get_values(opts, :setup_cmd) do
        [] -> Keyword.get(opts, :setup_cmd, [])
        many -> many
      end

    normalize_setup_commands(values)
  end

  defp normalize_setup_commands(nil), do: []

  defp normalize_setup_commands(value) when is_binary(value) do
    case String.trim(value) do
      "" -> []
      command -> [command]
    end
  end

  defp normalize_setup_commands(values) when is_list(values) do
    values
    |> Enum.flat_map(&normalize_setup_commands/1)
  end

  defp normalize_setup_commands(_), do: []
end
