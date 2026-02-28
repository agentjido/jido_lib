defmodule Jido.Lib.Github.Actions.DocsWriter.RunWriterPass do
  @moduledoc """
  Executes a writer pass and persists the guide draft artifact.
  """

  use Jido.Action,
    name: "docs_writer_run_writer_pass",
    description: "Run writer role for documentation guide draft",
    compensation: [max_retries: 0],
    schema: [
      iteration: [type: :integer, required: true],
      run_id: [type: :string, required: true],
      session_id: [type: :string, required: true],
      repo_dir: [type: :string, required: true],
      docs_brief: [type: {:or, [:string, nil]}, default: nil],
      writer_provider: [type: :atom, required: true],
      critic_provider: [type: :atom, required: true],
      single_pass: [type: :boolean, default: false],
      critique_v1: [type: {:or, [:map, nil]}, default: nil],
      needs_revision: [type: {:or, [:boolean, nil]}, default: nil],
      role_runtime_ready: [type: {:or, [:map, nil]}, default: nil],
      output_repo_context: [type: {:or, [:map, nil]}, default: nil],
      output_path: [type: {:or, [:string, nil]}, default: nil],
      codex_phase: [type: :atom, default: :triage],
      codex_fallback_phase: [type: {:or, [:atom, nil]}, default: :coding],
      timeout: [type: :integer, default: 300_000],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent],
      shell_session_server_mod: [type: :atom, default: Jido.Shell.ShellSessionServer],
      repo: [type: :string, required: true],
      owner: [type: :string, required: true],
      workspace_dir: [type: {:or, [:string, nil]}, default: nil],
      sprite_name: [type: {:or, [:string, nil]}, default: nil],
      sprite_config: [type: {:or, [:map, nil]}, default: nil],
      sprites_mod: [type: :atom, default: Sprites]
    ]

  alias Jido.Lib.Bots.Foundation.ArtifactStore
  alias Jido.Lib.Bots.Foundation.RoleRunner
  alias Jido.Lib.Github.Actions.DocsWriter.Helpers
  alias Jido.Lib.Github.Helpers, as: GithubHelpers

  @impl true
  def run(params, _context) do
    iteration = params.iteration

    cond do
      iteration not in [1, 2] ->
        {:error, {:docs_run_writer_pass_failed, :invalid_iteration}}

      iteration == 2 and params[:needs_revision] != true ->
        {:ok, Helpers.pass_through(params)}

      true ->
        run_iteration(params, iteration)
    end
  end

  defp run_iteration(params, iteration) do
    provider = params.writer_provider

    with :ok <- ensure_runtime_ready(provider, params),
         {:ok, result} <-
           RoleRunner.run(
             role: :writer,
             provider: provider,
             session_id: params.session_id,
             repo_dir: params.repo_dir,
             run_id: params.run_id,
             prompt_file: ".jido/prompts/jido_docs_writer_#{params.run_id}_v#{iteration}.txt",
             prompt: writer_prompt(params, iteration),
             phase: provider_phase(provider, params),
             fallback_phase: provider_fallback_phase(provider, params),
             timeout: params[:timeout] || 300_000,
             shell_agent_mod: params[:shell_agent_mod] || Jido.Shell.Agent,
             shell_session_server_mod:
               params[:shell_session_server_mod] || Jido.Shell.ShellSessionServer
           ),
         draft <- materialize_writer_draft(result, provider, params),
         {:ok, store} <- Helpers.artifact_store(params),
         {:ok, artifact} <-
           ArtifactStore.write_text(
             store,
             Helpers.writer_artifact_name(iteration),
             draft
           ) do
      key = Helpers.iteration_atom(iteration, :writer)

      {:ok,
       params
       |> Helpers.put_artifact(key, artifact)
       |> Map.put(key, draft)
       |> Map.put(:iterations_used, iteration)}
    else
      {:error, reason} -> {:error, {:docs_run_writer_pass_failed, reason}}
    end
  end

  defp ensure_runtime_ready(provider, params) do
    runtime_ready = params[:role_runtime_ready] || %{}

    if Map.get(runtime_ready, provider) == true do
      :ok
    else
      {:error, {:provider_runtime_not_ready, provider}}
    end
  end

  defp writer_prompt(params, 1) do
    output_repo = get_in(params, [:output_repo_context, :slug]) || "(unspecified)"
    has_grounded_context = is_binary(params[:grounded_context]) and params.grounded_context != ""
    content_metadata = params[:content_metadata] || %{}
    title = Map.get(content_metadata, :title, "Documentation Guide")
    # Known version constraints for ecosystem packages.  Kino is 0.x, not 2.x.
    version_map = %{
      "jido" => "~> 2.0",
      "jido_action" => "~> 2.0",
      "jido_signal" => "~> 2.0",
      "kino" => "~> 0.14"
    }

    ecosystem =
      content_metadata
      |> Map.get(:ecosystem_packages, ["jido"])
      |> Enum.map_join(", ", fn pkg ->
        vsn = Map.get(version_map, pkg, "~> 1.0")
        "{:#{pkg}, \"#{vsn}\"}"
      end)

    grounded_clause =
      if has_grounded_context do
        """
        - Ensure all API calls perfectly match the provided Grounding Context source code.
          DO NOT hallucinate functions or arities.
        - CRITICAL API PATTERN: `use Jido.Agent` generates `new/0`, `cmd/2`, `set/2` on
          YOUR module. So the correct calls are:
            agent = YourModule.new()           # NOT Jido.Agent.new(YourModule)
            {agent, dirs} = YourModule.cmd(agent, [Action])  # returns {agent, directives} 2-tuple
        """
      else
        ""
      end

    """
    You are an expert Elixir technical writer and educator.

    Use the following exhaustive brief and source code context to produce a complete Livebook.

    #{params[:docs_brief] || ""}

    Requirements:
    - Produce a valid Livebook (.livemd) document.
    - Ensure all API calls perfectly match the provided Grounding Context source code.
      DO NOT hallucinate functions or arities.
    - Write a clear, engaging narrative that connects the code blocks.
    - CRITICAL: NimbleOptions schemas only accept `type:`, `default:`, and `required:` keys.
      Do NOT use `doc:` in any schema definition — it causes a compilation error.
    #{grounded_clause}

    ═══════════════════════════════════════════════════════
    ║  THE GOLDEN TEMPLATE — Follow this EXACTLY         ║
    ═══════════════════════════════════════════════════════

    Your ENTIRE response must follow this structure. Do NOT wrap it in ```markdown
    or ```livemd fences. Start IMMEDIATELY with the %{ frontmatter map.

    %{
      title: "#{title}",
      description: "A concise description of this guide.",
      category: :docs,
      order: 10,
      tags: [:docs, :learn]
    }
    ---
    # #{title}

    Narrative introduction explaining what we'll build and why.

    ## Prerequisites

    Brief prerequisites (link to prior guides if available).

    ## Setup

    ```elixir
    Mix.install([#{ecosystem}])
    ```

    ## Defining Actions

    Actions receive `params` (validated inputs) and `context` (includes `context.state`
    with the current agent state). Return `{:ok, %{field: new_value}}` with the NEW values
    computed from current state.

    ```elixir
    defmodule Increment do
      use Jido.Action,
        name: "increment",
        schema: [amount: [type: :integer, default: 1]]

      @impl true
      def run(params, context) do
        current = context.state.count
        {:ok, %{count: current + params.amount}}
      end
    end
    ```

    CRITICAL: Actions access current state via `context.state`, NOT `params`.
    The return map `%{count: new_value}` is merged into the agent's state.

    ## Defining the Agent Module

    Explain the module definition grounded in the source context.

    ```elixir
    defmodule MyApp.Example do
      use Jido.Agent,
        name: "example",
        schema: [
          count: [type: :integer, default: 0]
        ]
    end
    ```

    ## Running Commands

    Demonstrate the API with concrete examples. Define variables BEFORE using them.
    CRITICAL: `use Jido.Agent` generates new/0, cmd/2, set/2 on YOUR module.
    Call `YourModule.new()` — NOT `Jido.Agent.new(YourModule)`.
    `cmd/2` returns `{agent, directives}` — a 2-tuple, NOT `{:ok, agent, directives}`.

    ```elixir
    # Create agent via the module's own new/0 (generated by `use Jido.Agent`)
    agent = MyApp.Example.new()
    # Run commands via the module's own cmd/2 — returns {agent, directives} 2-tuple
    {updated, _directives} = MyApp.Example.cmd(agent, [Increment])
    IO.inspect(updated.state, label: "State after command")
    ```

    ## Testing

    ```elixir
    ExUnit.start(autorun: false)

    defmodule MyApp.ExampleTest do
      use ExUnit.Case

      test "state transitions" do
        agent = MyApp.Example.new()
        assert agent.state.count == 0
      end
    end

    ExUnit.run()
    ```

    ## What to Try Next

    Pointers to related guides.

    ```elixir
    # CRITICAL: Assign the final module to DemoAgent for the visualizer
    DemoAgent = MyApp.Example
    ```

    ═══════════════════════════════════════════════════════
    ║  END OF GOLDEN TEMPLATE                            ║
    ═══════════════════════════════════════════════════════

    ABSOLUTE RULES:
    1. Your response starts with `%{` — no preamble, no fences, no "Here is…"
    2. Every ```elixir block must be valid, self-contained Elixir that compiles
    3. Define ALL variables before using them (no undefined variable errors)
    4. The LAST ```elixir block must contain `DemoAgent = YourAgentModule`
    5. Call `YourModule.new()` — NEVER `Jido.Agent.new(YourModule)` (FunctionClauseError!)
    6. Call `YourModule.cmd(agent, actions)` — the cmd/2 is on YOUR module, not Jido.Agent
    7. `cmd/2` returns `{agent, directives}` 2-tuple — NEVER `{:ok, agent, directives}` (MatchError!)
    8. Actions access current state via `context.state` — compute new values from current state
    9. NimbleOptions: ONLY `type:`, `default:`, `required:` — NEVER `doc:`

    Output target context:
    - Repo: #{output_repo}
    - Path: #{params[:output_path] || "(no path requested)"}
    """
    |> String.trim()
  end

  defp writer_prompt(params, 2) do
    instructions =
      get_in(params, [:critique_v1, :revision_instructions]) || "Address prior critique findings."

    content_metadata = params[:content_metadata] || %{}
    title = Map.get(content_metadata, :title, "Documentation Guide")

    """
    You are revising a .livemd documentation guide based on compiler and critic feedback.

    Original brief and grounding context:
    #{params[:docs_brief] || ""}

    Previous draft:
    #{params[:writer_draft_v1] || ""}

    Critic & Compiler revision instructions:
    #{instructions}

    ABSOLUTE RULES — Violating any of these causes an automatic rejection:
    1. Return the COMPLETE corrected .livemd file. Not a diff. Not a snippet. THE WHOLE FILE.
    2. Start IMMEDIATELY with `%{` frontmatter. No fences. No preamble. Example:
       %{
         title: "#{title}",
         description: "...",
         category: :docs,
         order: 10,
         tags: [:docs, :learn]
       }
       ---
    3. Use standard markdown with ```elixir code fences. NOT Livebook IDE format.
    4. NimbleOptions schemas: ONLY `type:`, `default:`, `required:`. NEVER `doc:`.
    5. Call `YourModule.new()` — NEVER `Jido.Agent.new(YourModule)` (FunctionClauseError!).
    6. Call `YourModule.cmd(agent, actions)` — the cmd/2 is on YOUR module, not Jido.Agent.
    7. `cmd/2` returns `{agent, directives}` 2-tuple — NEVER `{:ok, agent, directives}` (MatchError!).
    8. Actions access current state via `context.state` — compute new values from current state.
    9. Define ALL variables before referencing them (no undefined variable errors).
    10. The LAST ```elixir block MUST contain `DemoAgent = YourAgentModule`.
    11. Every ```elixir block must compile and run independently when concatenated.
    """
    |> String.trim()
  end

  defp provider_phase(:codex, params), do: params[:codex_phase] || :triage
  defp provider_phase(_provider, _params), do: :triage

  defp provider_fallback_phase(:codex, params), do: params[:codex_fallback_phase]
  defp provider_fallback_phase(_provider, _params), do: nil

  defp materialize_writer_draft(%{} = result, provider, params) do
    summary = result.summary || ""

    if provider == :codex and codex_status_summary?(summary) do
      read_generated_output(params, summary)
    else
      summary
    end
  end

  defp materialize_writer_draft(_result, _provider, _params), do: ""

  defp codex_status_summary?(text) when is_binary(text) do
    trimmed = String.trim(text)

    trimmed != "" and
      (String.contains?(trimmed, "Updated the guide at `") or
         String.starts_with?(trimmed, "Updated `") or
         String.contains?(trimmed, "No tests were run.") or
         String.contains?(trimmed, "No tests run.") or
         String.contains?(trimmed, "If you want, I can"))
  end

  defp codex_status_summary?(_), do: false

  defp read_generated_output(params, fallback) do
    output_path = params[:output_path]

    cond do
      not is_binary(output_path) or String.trim(output_path) == "" ->
        fallback

      true ->
        escaped = GithubHelpers.escape_path(output_path)
        shell_agent_mod = params[:shell_agent_mod] || Jido.Shell.Agent
        timeout = min(params[:timeout] || 300_000, 10_000)

        case GithubHelpers.run_in_dir(
               shell_agent_mod,
               params.session_id,
               params.repo_dir,
               "cat #{escaped}",
               timeout: timeout
             ) do
          {:ok, content} when is_binary(content) ->
            if String.trim(content) == "", do: fallback, else: content

          _ ->
            fallback
        end
    end
  end
end
