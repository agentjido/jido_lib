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
  require Logger

  @shortdoc "Triage a GitHub issue with Jido.Lib"

  alias Jido.Lib.Github.Agents.IssueTriageBot

  @supported_providers [:claude, :amp, :codex, :gemini]

  @doc false
  def handle_telemetry([:jido_runic, :runnable, status], _measurements, metadata, config) do
    node = metadata[:node]
    name = if node, do: node.name, else: :unknown
    elapsed = System.monotonic_time(:millisecond) - config.start_time
    elapsed_s = Float.round(elapsed / 1000, 1)

    icon = if status == :completed, do: "OK", else: "FAIL"
    label = name |> to_string() |> String.replace("_", " ")

    config.shell.info("[Runic] #{label} #{icon} (#{elapsed_s}s)")
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
        with_logger_level(:warning, fn ->
          triage =
            IssueTriageBot.triage(
              url,
              jido: Jido.Default,
              provider: provider,
              timeout: timeout,
              keep_sprite: opts[:keep_sprite] || false,
              setup_commands: opts[:setup_cmd] || [],
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
      setup_cmd: opts[:setup_cmd] || [],
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
        Mix.shell().error("triage failed: #{inspect(error)}")

      _ ->
        Mix.shell().error("triage failed with unknown status")
    end
  end

  defp with_logger_level(level, fun) when is_atom(level) and is_function(fun, 0) do
    previous_level = Logger.level()
    previous_agent_level = Logger.get_module_level(Jido.AgentServer)
    Logger.configure(level: level)
    Logger.put_module_level(Jido.AgentServer, :error)

    try do
      fun.()
    after
      Process.sleep(250)
      restore_agent_server_level(previous_agent_level)
      Logger.configure(level: previous_level)
    end
  end

  defp restore_agent_server_level([{Jido.AgentServer, level}]) when is_atom(level),
    do: Logger.put_module_level(Jido.AgentServer, level)

  defp restore_agent_server_level(_), do: Logger.delete_module_level(Jido.AgentServer)

  defp parse_provider(nil), do: :claude
  defp parse_provider(provider) when provider in @supported_providers, do: provider

  defp parse_provider(provider) when is_binary(provider) do
    normalized =
      provider
      |> String.trim()
      |> String.downcase()

    case normalized do
      "claude" ->
        :claude

      "amp" ->
        :amp

      "codex" ->
        :codex

      "gemini" ->
        :gemini

      _ ->
        Mix.raise("Invalid --provider #{inspect(provider)}. Allowed: claude, amp, codex, gemini")
    end
  end

  defp parse_provider(provider) do
    Mix.raise("Invalid --provider #{inspect(provider)}. Allowed: claude, amp, codex, gemini")
  end
end
