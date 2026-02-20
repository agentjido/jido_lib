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
  require Logger

  @shortdoc "Create a PR from a GitHub issue with Jido.Lib"

  alias Jido.Lib.Github.Agents.PrBot

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
        [:jido_runic, :runnable, :failed]
      ],
      &__MODULE__.handle_telemetry/4,
      %{shell: Mix.shell(), start_time: System.monotonic_time(:millisecond)}
    )

    Mix.shell().info("Starting GitHub PR bot...")
    Mix.shell().info("Issue: #{url}")

    result =
      try do
        with_logger_level(:warning, fn ->
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
        Mix.shell().error("pr bot failed: #{inspect(error)}")

      _ ->
        Mix.shell().error("pr bot failed with unknown status")
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
