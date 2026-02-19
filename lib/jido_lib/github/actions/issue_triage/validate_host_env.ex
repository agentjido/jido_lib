defmodule Jido.Lib.Github.Actions.IssueTriage.ValidateHostEnv do
  @moduledoc """
  Validate required host env vars before any sprite workflow work begins.
  """

  use Jido.Action,
    name: "validate_host_env",
    description: "Validate host env contract for GitHub triage",
    schema: [
      run_id: [type: :string, required: true],
      owner: [type: :string, required: true],
      repo: [type: :string, required: true],
      issue_number: [type: :integer, required: true],
      issue_url: [type: {:or, [:string, nil]}, default: nil],
      timeout: [type: :integer, default: 300_000],
      keep_workspace: [type: :boolean, default: false],
      keep_sprite: [type: :boolean, default: false],
      setup_commands: [type: {:list, :string}, default: []],
      prompt: [type: {:or, [:string, nil]}, default: nil],
      observer_pid: [type: {:or, [:any, nil]}, default: nil],
      sprite_config: [type: :map, required: true],
      sprites_mod: [type: :atom, default: Sprites],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent],
      shell_session_mod: [type: :atom, default: Jido.Shell.ShellSession]
    ]

  alias Jido.Lib.Github.Actions.IssueTriage.Helpers

  @required_auth_vars [
    "ANTHROPIC_AUTH_TOKEN",
    "ANTHROPIC_API_KEY",
    "CLAUDE_CODE_API_KEY"
  ]

  @forward_vars [
    "ANTHROPIC_BASE_URL",
    "ANTHROPIC_AUTH_TOKEN",
    "ANTHROPIC_API_KEY",
    "CLAUDE_CODE_API_KEY",
    "ANTHROPIC_DEFAULT_SMALL_MODEL",
    "ANTHROPIC_DEFAULT_LARGE_MODEL",
    "ANTHROPIC_DEFAULT_THINKING_MODEL",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL",
    "ANTHROPIC_DEFAULT_SONNET_MODEL",
    "ANTHROPIC_DEFAULT_OPUS_MODEL",
    "GH_TOKEN",
    "GITHUB_TOKEN"
  ]

  @impl true
  def run(params, _context) do
    validate_host_env!()
    {:ok, Helpers.pass_through(params)}
  end

  @doc """
  Validate required host env vars for sprite triage + ZAI Claude routing.
  """
  @spec validate_host_env!() :: :ok | no_return()
  def validate_host_env! do
    require_env!("SPRITES_TOKEN", "SPRITES_TOKEN environment variable not set")
    require_env!("ANTHROPIC_BASE_URL", "ANTHROPIC_BASE_URL environment variable not set")
    require_any_env!(@required_auth_vars, zai_auth_error_message())

    require_any_env!(
      ["GH_TOKEN", "GITHUB_TOKEN"],
      "GH_TOKEN or GITHUB_TOKEN environment variable not set"
    )

    :ok
  end

  @doc """
  Build the env map propagated into Sprite sessions.
  """
  @spec build_sprite_env() :: map()
  def build_sprite_env do
    @forward_vars
    |> Enum.reduce(
      %{
        "GH_PROMPT_DISABLED" => "1",
        "GIT_TERMINAL_PROMPT" => "0"
      },
      fn key, acc ->
        case System.get_env(key) do
          nil -> acc
          value -> Map.put(acc, key, value)
        end
      end
    )
  end

  defp require_env!(key, message) do
    if present?(System.get_env(key)) do
      :ok
    else
      raise message
    end
  end

  defp require_any_env!(keys, message) when is_list(keys) do
    if Enum.any?(keys, &present?(System.get_env(&1))) do
      :ok
    else
      raise message
    end
  end

  defp zai_auth_error_message do
    "One of ANTHROPIC_AUTH_TOKEN, ANTHROPIC_API_KEY, or CLAUDE_CODE_API_KEY must be set"
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false
end
