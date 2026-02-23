defmodule Mix.Tasks.JidoLib.Github.Docs do
  @moduledoc """
  Run persistent multi-repo documentation writer workflow.

  ## Usage

      mix jido_lib.github.docs path/to/brief.md \
        --repo owner/repo[:alias] --repo owner2/repo2[:alias] \
        --output-repo alias_or_slug --sprite-name my-sprite

  ## Options

  - `--timeout` - Pipeline timeout in seconds (default: 600)
  - `--repo` - Repository context spec `owner/repo[:alias]` (repeatable, required)
  - `--output-repo` - Alias or slug identifying writable output repo (required)
  - `--sprite-name` - Explicit persistent sprite name (required)
  - `--output-path` - Repo-relative path to write guide when publishing
  - `--publish` - Enable branch/commit/push/PR publication flow
  - `--writer` - Writer provider: claude | amp | codex | gemini (default: codex)
  - `--critic` - Critic provider: claude | amp | codex | gemini (default: claude)
  - `--max-revisions` - Revision budget (allowed: 0 or 1; default: 1)
  - `--workspace-root` - Override sprite workspace root (default: /work/docs/<sprite_name>)
  - `--setup-cmd CMD` - Setup command to run in output repo (repeatable)
  - `--destroy-sprite` - Destroy sprite at end (default keeps sprite)
  """

  use Mix.Task

  @shortdoc "Run DocumentationWriterBot"

  alias Jido.Lib.Github.Agents.DocumentationWriterBot
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
          repo: :keep,
          output_repo: :string,
          sprite_name: :string,
          output_path: :string,
          publish: :boolean,
          writer: :string,
          critic: :string,
          max_revisions: :integer,
          workspace_root: :string,
          setup_cmd: :keep,
          destroy_sprite: :boolean
        ],
        aliases: [t: :timeout]
      )

    brief_file =
      List.first(args) ||
        Mix.raise(
          "Usage: mix jido_lib.github.docs <brief_file> --repo ... --output-repo ... --sprite-name ..."
        )

    brief = read_brief_file!(brief_file)
    repos = repo_specs_from_opts(opts)

    if repos == [] do
      Mix.raise("At least one --repo owner/repo[:alias] value is required")
    end

    output_repo = opts[:output_repo] || Mix.raise("--output-repo is required")
    sprite_name = opts[:sprite_name] || Mix.raise("--sprite-name is required")

    timeout = (opts[:timeout] || 600) * 1_000

    result =
      DocumentationWriterBot.run_brief(brief,
        repos: repos,
        output_repo: output_repo,
        sprite_name: sprite_name,
        output_path: opts[:output_path],
        publish: opts[:publish] == true,
        writer_provider: parse_provider(opts[:writer], :writer, :codex),
        critic_provider: parse_provider(opts[:critic], :critic, :claude),
        max_revisions: normalize_max_revisions(opts[:max_revisions] || 1),
        workspace_root: opts[:workspace_root],
        setup_commands: setup_commands_from_opts(opts),
        keep_sprite: opts[:destroy_sprite] != true,
        timeout: timeout,
        jido: Jido.Default,
        debug: false,
        observer: Mix.shell()
      )

    print_summary(result)
    result
  end

  @doc false
  def parse_provider(nil, _role, default), do: default

  def parse_provider(provider, role, _default) do
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

  @doc false
  def read_brief_file!(path) when is_binary(path) do
    case File.read(path) do
      {:ok, content} when is_binary(content) ->
        if String.trim(content) == "" do
          Mix.raise("Brief file is empty: #{path}")
        else
          content
        end

      {:error, reason} ->
        Mix.raise("Unable to read brief file #{path}: #{inspect(reason)}")
    end
  end

  @doc false
  def repo_specs_from_opts(opts) when is_list(opts) do
    case Keyword.get_values(opts, :repo) do
      [] -> normalize_string_list(Keyword.get(opts, :repos, []))
      values -> normalize_string_list(values)
    end
  end

  @doc false
  def setup_commands_from_opts(opts) when is_list(opts) do
    case Keyword.get_values(opts, :setup_cmd) do
      [] -> normalize_string_list(Keyword.get(opts, :setup_cmd, []))
      values -> normalize_string_list(values)
    end
  end

  defp normalize_string_list(nil), do: []

  defp normalize_string_list(value) when is_binary(value) do
    case String.trim(value) do
      "" -> []
      text -> [text]
    end
  end

  defp normalize_string_list(values) when is_list(values) do
    values
    |> Enum.flat_map(&normalize_string_list/1)
  end

  defp normalize_string_list(_), do: []

  defp print_summary(result) when is_map(result) do
    Mix.shell().info("Status: #{result[:status] || :unknown}")
    Mix.shell().info("Run ID: #{result[:run_id] || "n/a"}")
    Mix.shell().info("Decision: #{result[:decision] || "n/a"}")
    Mix.shell().info("Writer: #{result[:writer_provider] || "n/a"}")
    Mix.shell().info("Critic: #{result[:critic_provider] || "n/a"}")
    Mix.shell().info("Published: #{result[:published] == true}")

    if path = result[:output_path] do
      Mix.shell().info("Output path: #{path}")
    end

    if pr_url = result[:pr_url] do
      Mix.shell().info("PR: #{pr_url}")
    end

    if error = result[:error] do
      Mix.shell().error("documentation writer failed: #{format_error(error)}")
    end
  end

  defp format_error({:pipeline_failed, failures, _partial}) when is_list(failures) do
    "{:pipeline_failed, failures=#{length(failures)}}"
  end

  defp format_error({:pipeline_failed, failures}) when is_list(failures) do
    "{:pipeline_failed, failures=#{length(failures)}}"
  end

  defp format_error(%{__exception__: true} = error), do: Exception.message(error)

  defp format_error(error) do
    inspect(error, limit: 20, printable_limit: 500)
  end
end
