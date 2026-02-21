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
    cond do
      env_probe_command?(command) ->
        env_probe_response(command)

      String.contains?(command, "gh repo view") and
          String.contains?(command, "defaultBranchRef") ->
        {:ok, "main"}

      String.contains?(command, "${GH_TOKEN:-}") and
        String.contains?(command, "${GITHUB_TOKEN:-}") and
          String.contains?(command, "echo present") ->
        {:ok, "present"}

      String.contains?(command, "${ANTHROPIC_AUTH_TOKEN:-}") and
          String.contains?(command, "echo present") ->
        {:ok, "present"}

      String.contains?(command, "${ANTHROPIC_API_KEY:-}") and
          String.contains?(command, "echo present") ->
        {:ok, "present"}

      String.contains?(command, "${CLAUDE_CODE_API_KEY:-}") and
          String.contains?(command, "echo present") ->
        {:ok, "present"}

      String.contains?(command, "${OPENAI_API_KEY:-}") and
          String.contains?(command, "echo present") ->
        {:ok, "present"}

      String.contains?(command, "${AMP_API_KEY:-}") and
          String.contains?(command, "echo present") ->
        {:ok, "present"}

      String.contains?(command, "${GEMINI_API_KEY:-}") and
          String.contains?(command, "echo present") ->
        {:ok, "present"}

      String.contains?(command, "${GOOGLE_API_KEY:-}") and
          String.contains?(command, "echo present") ->
        {:ok, "present"}

      String.contains?(command, "${GOOGLE_GENAI_USE_VERTEXAI:-}") and
          String.contains?(command, "echo present") ->
        {:ok, "present"}

      String.contains?(command, "${GOOGLE_GENAI_USE_GCA:-}") and
          String.contains?(command, "echo present") ->
        {:ok, "present"}

      tool_check?(command, "gh") ->
        {:ok, "present"}

      tool_check?(command, "git") ->
        {:ok, "present"}

      tool_check?(command, "claude") ->
        {:ok, "present"}

      tool_check?(command, "amp") ->
        {:ok, "present"}

      tool_check?(command, "codex") ->
        {:ok, "present"}

      tool_check?(command, "gemini") ->
        {:ok, "present"}

      String.contains?(command, "ANTHROPIC_BASE_URL") and
          String.contains?(command, "echo present") ->
        {:ok, "present"}

      String.contains?(command, "CLAUDE_CODE_API_KEY") and
          String.contains?(command, "ANTHROPIC_AUTH_TOKEN") ->
        {:ok, "ANTHROPIC_AUTH_TOKEN"}

      String.contains?(command, "gh auth status") ->
        {:ok, "authenticated"}

      String.contains?(command, "gh auth setup-git") ->
        {:ok, "configured"}

      String.contains?(command, "gh api user --jq .login") ->
        {:ok, "testuser"}

      String.contains?(command, "claude --help") ->
        {:ok, "--output-format stream-json --include-partial-messages"}

      String.contains?(command, "amp --help") ->
        {:ok, "--execute --stream-json --dangerously-allow-all"}

      String.contains?(command, "codex --help") ->
        {:ok, "codex exec --json --full-auto"}

      String.contains?(command, "codex exec --help") ->
        {:ok, "exec --json"}

      String.contains?(command, "gemini --help") ->
        {:ok, "--output-format stream-json --approval-mode"}

      String.contains?(command, "codex login --with-api-key") ->
        {:ok, "ok"}

      String.contains?(command, "codex login status") ->
        {:ok, "ok"}

      String.contains?(command, "gh issue view") ->
        {:ok,
         Jason.encode!(%{
           "title" => "Bug: Widget crashes on nil",
           "body" => "Widget.call/1 crashes when passed nil input.",
           "labels" => [%{"name" => "bug"}],
           "author" => %{"login" => "testuser"},
           "state" => "OPEN",
           "url" => "https://github.com/test/repo/issues/42"
         })}

      String.contains?(command, "git clone") ->
        {:ok, "Cloning into '/tmp/repo'..."}

      String.contains?(command, "git fetch origin") ->
        {:ok, "Fetched"}

      String.contains?(command, "git checkout -b") ->
        {:ok, "Switched to a new branch"}

      String.contains?(command, "git checkout") ->
        {:ok, "Switched branch"}

      String.contains?(command, "git pull --ff-only origin") ->
        {:ok, "Already up to date."}

      String.contains?(command, "git show-ref --verify --quiet") ->
        {:ok, "missing"}

      String.contains?(command, "git ls-remote --exit-code --heads") ->
        {:ok, "missing"}

      String.contains?(command, "git rev-list --count") ->
        {:ok, "1"}

      String.contains?(command, "git status --porcelain") ->
        {:ok, ""}

      String.contains?(command, "git rev-parse HEAD") ->
        {:ok, "head-sha-123"}

      String.contains?(command, "git rev-parse") ->
        {:ok, "base-sha-main"}

      String.contains?(command, "git add -A && git commit -m") ->
        {:ok, "[feature 123] fix commit"}

      String.contains?(command, "git remote get-url origin") ->
        {:ok, "https://github.com/test/repo.git"}

      String.contains?(command, "git push -u origin") ->
        {:ok, "branch pushed"}

      String.contains?(command, "gh pr list") ->
        {:ok, "[]"}

      String.contains?(command, "gh pr create") ->
        {:ok, "https://github.com/test/repo/pull/7"}

      String.contains?(command, "mix deps.get") ->
        {:ok, "Resolved and locked"}

      String.contains?(command, "mix compile") ->
        {:ok, "Compiled 42 files"}

      String.contains?(command, "claude -p") ->
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

      String.contains?(command, "gh issue comment") ->
        {:ok, "https://github.com/test/repo/issues/42#issuecomment-1"}

      true ->
        {:ok, "ok"}
    end
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
