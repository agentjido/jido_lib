defmodule Jido.Lib.Bots.Foundation.RunContext do
  @moduledoc """
  Validated intake envelope for dual-role writer/critic bot runs.
  """

  alias Jido.Lib.Github.Actions.ValidateHostEnv
  alias Jido.Lib.Github.Helpers

  @schema Zoi.struct(
            __MODULE__,
            %{
              run_id: Zoi.string(),
              issue_url: Zoi.string(),
              owner: Zoi.string(),
              repo: Zoi.string(),
              issue_number: Zoi.integer(),
              writer_provider: Zoi.atom(),
              critic_provider: Zoi.atom(),
              max_revisions: Zoi.integer() |> Zoi.default(1),
              post_comment: Zoi.boolean() |> Zoi.default(true),
              timeout: Zoi.integer() |> Zoi.default(300_000),
              keep_workspace: Zoi.boolean() |> Zoi.default(false),
              keep_sprite: Zoi.boolean() |> Zoi.default(false),
              setup_commands: Zoi.array(Zoi.string()) |> Zoi.default([]),
              prompt: Zoi.string() |> Zoi.nullish(),
              sprite_config: Zoi.map() |> Zoi.default(%{}),
              sprites_mod: Zoi.any() |> Zoi.optional(),
              shell_agent_mod: Zoi.any() |> Zoi.optional(),
              shell_session_mod: Zoi.any() |> Zoi.optional(),
              observer_pid: Zoi.any() |> Zoi.nullish(),
              started_at: Zoi.string() |> Zoi.nullish()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    attrs =
      attrs
      |> normalize_urls()
      |> normalize_providers()
      |> normalize_run_id()
      |> normalize_setup_commands()
      |> normalize_sprite_config()
      |> Map.put_new(:started_at, DateTime.utc_now() |> DateTime.to_iso8601())

    with {:ok, parsed} <- Zoi.parse(@schema, attrs),
         :ok <- validate_revision_budget(parsed.max_revisions) do
      {:ok, parsed}
    end
  rescue
    error in [ArgumentError] ->
      {:error, error}
  end

  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs) do
    case new(attrs) do
      {:ok, parsed} -> parsed
      {:error, reason} -> raise ArgumentError, "invalid run context: #{inspect(reason)}"
    end
  end

  @spec from_issue_url(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def from_issue_url(issue_url, opts \\ []) when is_binary(issue_url) and is_list(opts) do
    {owner, repo, issue_number} = Helpers.parse_issue_url!(issue_url)

    attrs = %{
      issue_url: issue_url,
      owner: owner,
      repo: repo,
      issue_number: issue_number,
      writer_provider: Keyword.get(opts, :writer_provider, :claude),
      critic_provider: Keyword.get(opts, :critic_provider, :codex),
      max_revisions: Keyword.get(opts, :max_revisions, 1),
      post_comment: Keyword.get(opts, :post_comment, true),
      timeout: Keyword.get(opts, :timeout, 300_000),
      keep_workspace: Keyword.get(opts, :keep_workspace, false),
      keep_sprite: Keyword.get(opts, :keep_sprite, false),
      setup_commands: Keyword.get(opts, :setup_commands, []),
      prompt: Keyword.get(opts, :prompt),
      sprite_config: Keyword.get(opts, :sprite_config),
      sprites_mod: Keyword.get(opts, :sprites_mod, Sprites),
      shell_agent_mod: Keyword.get(opts, :shell_agent_mod, Jido.Shell.Agent),
      shell_session_mod: Keyword.get(opts, :shell_session_mod, Jido.Shell.ShellSession),
      observer_pid: Keyword.get(opts, :observer_pid)
    }

    new(attrs)
  end

  @spec to_intake(t() | map()) :: map()
  def to_intake(%__MODULE__{} = context) do
    %{
      run_id: context.run_id,
      issue_url: context.issue_url,
      owner: context.owner,
      repo: context.repo,
      issue_number: context.issue_number,
      provider: context.writer_provider,
      writer_provider: context.writer_provider,
      critic_provider: context.critic_provider,
      max_revisions: context.max_revisions,
      post_comment: context.post_comment,
      timeout: context.timeout,
      keep_workspace: context.keep_workspace,
      keep_sprite: context.keep_sprite,
      setup_commands: context.setup_commands,
      prompt: context.prompt,
      sprite_config: context.sprite_config,
      sprites_mod: context.sprites_mod || Sprites,
      shell_agent_mod: context.shell_agent_mod || Jido.Shell.Agent,
      shell_session_mod: context.shell_session_mod || Jido.Shell.ShellSession,
      observer_pid: context.observer_pid,
      started_at: context.started_at,
      agent_mode: :triage,
      comment_mode: :triage_report
    }
  end

  def to_intake(%{} = context), do: context

  defp normalize_urls(%{issue_url: issue_url} = attrs) when is_binary(issue_url) do
    case Map.has_key?(attrs, :owner) and Map.has_key?(attrs, :repo) and
           Map.has_key?(attrs, :issue_number) do
      true ->
        attrs

      false ->
        {owner, repo, issue_number} = Helpers.parse_issue_url!(issue_url)

        attrs
        |> Map.put(:owner, owner)
        |> Map.put(:repo, repo)
        |> Map.put(:issue_number, issue_number)
    end
  end

  defp normalize_urls(attrs), do: attrs

  defp normalize_providers(attrs) do
    writer_provider = Helpers.provider_normalize!(Map.get(attrs, :writer_provider, :claude))
    critic_provider = Helpers.provider_normalize!(Map.get(attrs, :critic_provider, :codex))

    attrs
    |> Map.put(:writer_provider, writer_provider)
    |> Map.put(:critic_provider, critic_provider)
  end

  defp normalize_run_id(attrs) do
    run_id =
      case Map.get(attrs, :run_id) do
        value when is_binary(value) and value != "" ->
          value

        _ ->
          :crypto.strong_rand_bytes(6)
          |> Base.encode16(case: :lower)
      end

    Map.put(attrs, :run_id, run_id)
  end

  defp normalize_setup_commands(attrs) do
    commands =
      attrs
      |> Map.get(:setup_commands, [])
      |> normalize_command_list()

    Map.put(attrs, :setup_commands, commands)
  end

  defp normalize_command_list(nil), do: []

  defp normalize_command_list(value) when is_binary(value) do
    case String.trim(value) do
      "" -> []
      command -> [command]
    end
  end

  defp normalize_command_list(values) when is_list(values) do
    values
    |> Enum.flat_map(&normalize_command_list/1)
  end

  defp normalize_command_list(_), do: []

  defp normalize_sprite_config(attrs) do
    config =
      case Map.get(attrs, :sprite_config) do
        %{} = map when map_size(map) > 0 ->
          map

        _ ->
          %{
            token: System.get_env("SPRITES_TOKEN"),
            create: true,
            env: ValidateHostEnv.build_sprite_env(Map.get(attrs, :writer_provider, :claude))
          }
      end

    Map.put(attrs, :sprite_config, config)
  end

  defp validate_revision_budget(max_revisions) when max_revisions in [0, 1], do: :ok

  defp validate_revision_budget(other) do
    {:error,
     ArgumentError.exception(
       "max_revisions must be 0 or 1 for v1 implementation, got: #{inspect(other)}"
     )}
  end
end
