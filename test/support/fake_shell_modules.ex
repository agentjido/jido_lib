defmodule Jido.Lib.Test.FakeShellState do
  @moduledoc false

  use Agent

  def start_link(_opts \\ []) do
    Agent.start(
      fn ->
        %{runs: [], stops: [], starts: [], failures: [], sprites: %{}, sprite_destroys: []}
      end,
      name: __MODULE__
    )
  end

  def ensure_started! do
    case Process.whereis(__MODULE__) do
      nil ->
        case start_link() do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end

      _pid ->
        :ok
    end
  end

  def reset! do
    ensure_started!()

    Agent.update(__MODULE__, fn _ ->
      %{runs: [], stops: [], starts: [], failures: [], sprites: %{}, sprite_destroys: []}
    end)
  end

  def add_run(entry), do: Agent.update(__MODULE__, &%{&1 | runs: [entry | &1.runs]})
  def add_stop(session_id), do: Agent.update(__MODULE__, &%{&1 | stops: [session_id | &1.stops]})
  def add_start(entry), do: Agent.update(__MODULE__, &%{&1 | starts: [entry | &1.starts]})

  def add_failure(match, reason) when is_binary(match) do
    Agent.update(__MODULE__, &%{&1 | failures: [{match, reason} | &1.failures]})
  end

  def put_sprite(name) when is_binary(name) do
    Agent.update(__MODULE__, fn state ->
      %{state | sprites: Map.put(state.sprites, name, true)}
    end)
  end

  def sprite_exists?(name) when is_binary(name) do
    Agent.get(__MODULE__, fn state -> Map.get(state.sprites, name, false) end)
  end

  def destroy_sprite(name) when is_binary(name) do
    Agent.update(__MODULE__, fn state ->
      %{
        state
        | sprites: Map.delete(state.sprites, name),
          sprite_destroys: [name | state.sprite_destroys]
      }
    end)
  end

  def runs, do: Agent.get(__MODULE__, &Enum.reverse(&1.runs))
  def stops, do: Agent.get(__MODULE__, &Enum.reverse(&1.stops))
  def starts, do: Agent.get(__MODULE__, &Enum.reverse(&1.starts))
  def failures, do: Agent.get(__MODULE__, &Enum.reverse(&1.failures))
  def sprite_destroys, do: Agent.get(__MODULE__, &Enum.reverse(&1.sprite_destroys))
end

defmodule Jido.Lib.Test.FakeShellSession do
  @moduledoc false

  def start_with_vfs(workspace_id, opts \\ []) when is_binary(workspace_id) and is_list(opts) do
    Jido.Lib.Test.FakeShellState.ensure_started!()
    Jido.Lib.Test.FakeShellState.add_start({workspace_id, opts})
    {:ok, "sess-#{workspace_id}"}
  end
end

defmodule Jido.Lib.Test.FakeShellAgent do
  @moduledoc false

  def run(session_id, command, _opts \\ []) when is_binary(session_id) and is_binary(command) do
    Jido.Lib.Test.FakeShellState.ensure_started!()
    Jido.Lib.Test.FakeShellState.add_run({session_id, command})

    case matching_failure(command) do
      {:error, reason} ->
        {:error, reason}

      nil ->
        scripted_response(command)
    end
  end

  def stop(session_id) when is_binary(session_id) do
    Jido.Lib.Test.FakeShellState.ensure_started!()
    Jido.Lib.Test.FakeShellState.add_stop(session_id)
    :ok
  end

  defp matching_failure(command) do
    Enum.find_value(Jido.Lib.Test.FakeShellState.failures(), fn {pattern, reason} ->
      if String.contains?(command, pattern), do: {:error, reason}, else: nil
    end)
  end

  defp scripted_response(command) do
    env_probe_or_nil(command) ||
      env_presence_or_nil(command) ||
      tool_presence_or_nil(command) ||
      static_command_response(command) ||
      {:ok, "ok"}
  end

  defp env_probe_or_nil(command) do
    if env_probe_command?(command), do: env_probe_response(command), else: nil
  end

  defp env_presence_or_nil(command) do
    command_rules = [
      {["${GH_TOKEN:-}", "${GITHUB_TOKEN:-}", "echo present"], {:ok, "present"}},
      {["${ANTHROPIC_AUTH_TOKEN:-}", "echo present"], {:ok, "present"}},
      {["${ANTHROPIC_API_KEY:-}", "echo present"], {:ok, "present"}},
      {["${CLAUDE_CODE_API_KEY:-}", "echo present"], {:ok, "present"}},
      {["${OPENAI_API_KEY:-}", "echo present"], {:ok, "present"}},
      {["${AMP_API_KEY:-}", "echo present"], {:ok, "present"}},
      {["${GEMINI_API_KEY:-}", "echo present"], {:ok, "present"}},
      {["${GOOGLE_API_KEY:-}", "echo present"], {:ok, "present"}},
      {["${GOOGLE_GENAI_USE_VERTEXAI:-}", "echo present"], {:ok, "present"}},
      {["${GOOGLE_GENAI_USE_GCA:-}", "echo present"], {:ok, "present"}},
      {["ANTHROPIC_BASE_URL", "echo present"], {:ok, "present"}},
      {["CLAUDE_CODE_API_KEY", "ANTHROPIC_AUTH_TOKEN"], {:ok, "ANTHROPIC_AUTH_TOKEN"}}
    ]

    match_command_rules(command, command_rules)
  end

  defp tool_presence_or_nil(command) do
    tools = ["gh", "git", "claude", "amp", "codex", "gemini"]

    if Enum.any?(tools, &tool_check?(command, &1)), do: {:ok, "present"}, else: nil
  end

  defp static_command_response(command) do
    command_rules = [
      {["gh repo view", "defaultBranchRef"], {:ok, "main"}},
      {["gh auth status"], {:ok, "authenticated"}},
      {["gh auth setup-git"], {:ok, "configured"}},
      {["gh api user --jq .login"], {:ok, "testuser"}},
      {["claude --help"], {:ok, "--output-format stream-json --include-partial-messages"}},
      {["amp --help"], {:ok, "--execute --stream-json --dangerously-allow-all"}},
      {["codex --help"], {:ok, "codex exec --json --full-auto"}},
      {["codex exec --help"], {:ok, "exec --json"}},
      {["codex exec"], &codex_exec_response/0},
      {["gemini --help"], {:ok, "--output-format stream-json --approval-mode"}},
      {["codex login --with-api-key"], {:ok, "ok"}},
      {["codex login status"], {:ok, "ok"}},
      {["gh issue view"], &issue_view_response/0},
      {["git clone"], {:ok, "Cloning into '/tmp/repo'..."}},
      {["git fetch origin"], {:ok, "Fetched"}},
      {["git checkout -b"], {:ok, "Switched to a new branch"}},
      {["git checkout"], {:ok, "Switched branch"}},
      {["git pull --ff-only origin"], {:ok, "Already up to date."}},
      {["git show-ref --verify --quiet"], {:ok, "missing"}},
      {["git ls-remote --exit-code --heads"], {:ok, "missing"}},
      {["git rev-list --count"], {:ok, "1"}},
      {["git status --porcelain"], {:ok, ""}},
      {["git rev-parse HEAD"], {:ok, "head-sha-123"}},
      {["git rev-parse"], {:ok, "base-sha-main"}},
      {["git add -A && git commit -m"], {:ok, "[feature 123] fix commit"}},
      {["git remote get-url origin"], {:ok, "https://github.com/test/repo.git"}},
      {["git push -u origin"], {:ok, "branch pushed"}},
      {["gh pr list"], {:ok, "[]"}},
      {["gh pr create"], {:ok, "https://github.com/test/repo/pull/7"}},
      {["mix deps.get"], {:ok, "Resolved and locked"}},
      {["mix compile"], {:ok, "Compiled 42 files"}},
      {["claude -p"], &claude_prompt_response/0},
      {["gh issue comment"], {:ok, "https://github.com/test/repo/issues/42#issuecomment-1"}}
    ]

    match_command_rules(command, command_rules)
  end

  defp match_command_rules(command, rules) when is_binary(command) and is_list(rules) do
    Enum.find_value(rules, fn {patterns, response} ->
      if matches_all?(command, patterns), do: resolve_response(response), else: nil
    end)
  end

  defp matches_all?(command, patterns) when is_binary(command) and is_list(patterns) do
    Enum.all?(patterns, &String.contains?(command, &1))
  end

  defp resolve_response(response) when is_function(response, 0), do: response.()
  defp resolve_response(response), do: response

  defp issue_view_response do
    {:ok,
     Jason.encode!(%{
       "title" => "Bug: Widget crashes on nil",
       "body" => "Widget.call/1 crashes when passed nil input.",
       "labels" => [%{"name" => "bug"}],
       "author" => %{"login" => "testuser"},
       "state" => "OPEN",
       "url" => "https://github.com/test/repo/issues/42"
     })}
  end

  defp claude_prompt_response do
    {:ok,
     [
       Jason.encode!(%{"type" => "system", "subtype" => "init", "model" => "claude-test"}),
       Jason.encode!(%{
         "type" => "stream_event",
         "event" => %{
           "type" => "content_block_delta",
           "delta" => %{"type" => "text_delta", "text" => "## Investigation Report\n\n"}
         }
       }),
       Jason.encode!(%{
         "type" => "result",
         "subtype" => "success",
         "is_error" => false,
         "result" => "## Investigation Report\n\nRoot cause found."
       })
     ]
     |> Enum.join("\n")}
  end

  defp codex_exec_response do
    critique =
      Jason.encode!(%{
        verdict: "accept",
        severity: "low",
        findings: [],
        revision_instructions: "",
        confidence: 0.9
      })

    {:ok,
     [
       Jason.encode!(%{"type" => "turn.started"}),
       Jason.encode!(%{"type" => "turn.completed", "output_text" => critique})
     ]
     |> Enum.join("\n")}
  end

  defp env_probe_command?(command) when is_binary(command) do
    String.contains?(command, "if [ -n \"${") and
      String.contains?(command, "echo present") and
      String.contains?(command, "echo missing")
  end

  defp env_probe_response(command) do
    case Regex.run(~r/\$\{([A-Z0-9_]+):-\}/, command, capture: :all_but_first) do
      [env_key] ->
        value = System.get_env(env_key)

        if is_binary(value) and value != "" do
          {:ok, "present"}
        else
          {:ok, "missing"}
        end

      _ ->
        {:ok, "ok"}
    end
  end

  defp tool_check?(command, tool) when is_binary(command) and is_binary(tool) do
    String.contains?(command, "command -v #{tool}") or
      String.contains?(command, "command -v '#{tool}'")
  end
end

defmodule Jido.Lib.Test.FakeSprites do
  @moduledoc false

  def new(token, opts \\ []) when is_binary(token) and is_list(opts) do
    %{token: token, opts: opts}
  end

  def sprite(client, name) when is_binary(name) do
    %{client: client, name: name}
  end

  def get_sprite(_client, name) when is_binary(name) do
    Jido.Lib.Test.FakeShellState.ensure_started!()

    if Jido.Lib.Test.FakeShellState.sprite_exists?(name) do
      {:ok, %{"name" => name, "status" => "tracked"}}
    else
      {:error, :not_found}
    end
  end

  def destroy(%{name: name}) when is_binary(name) do
    Jido.Lib.Test.FakeShellState.ensure_started!()
    Jido.Lib.Test.FakeShellState.destroy_sprite(name)
    :ok
  end
end
