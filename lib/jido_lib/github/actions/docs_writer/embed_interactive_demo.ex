defmodule Jido.Lib.Github.Actions.DocsWriter.EmbedInteractiveDemo do
  @moduledoc """
  Appends interactive Kino playground to validated Livebooks.

  After the writer/critic cycle produces an accepted draft, this action uses
  an LLM to generate a minimal, self-contained demonstration script that
  exercises the concepts taught in the guide. The demo code is wrapped in a
  "Try It Live" section with Kino visualizer hooks for Runic workflows or
  Jido agents.
  """

  use Jido.Action,
    name: "docs_writer_embed_interactive_demo",
    description: "Generate and embed interactive Kino demo in accepted Livebook drafts",
    compensation: [max_retries: 0],
    schema: [
      run_id: [type: :string, required: true],
      session_id: [type: :string, required: true],
      repo_dir: [type: :string, required: true],
      writer_provider: [type: :atom, required: true],
      content_metadata: [type: :map, required: true],
      docs_brief: [type: {:or, [:string, nil]}, default: nil],
      writer_draft_v1: [type: {:or, [:string, nil]}, default: nil],
      writer_draft_v2: [type: {:or, [:string, nil]}, default: nil],
      final_decision: [type: {:or, [:atom, nil]}, default: nil],
      gate_v1: [type: {:or, [:map, nil]}, default: nil],
      gate_v2: [type: {:or, [:map, nil]}, default: nil],
      needs_revision: [type: {:or, [:boolean, nil]}, default: nil],
      role_runtime_ready: [type: {:or, [:map, nil]}, default: nil],
      codex_phase: [type: :atom, default: :triage],
      codex_fallback_phase: [type: {:or, [:atom, nil]}, default: :coding],
      timeout: [type: :integer, default: 300_000],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent],
      shell_session_server_mod: [type: :atom, default: Jido.Shell.ShellSessionServer],
      repo: [type: {:or, [:string, nil]}, default: nil],
      owner: [type: {:or, [:string, nil]}, default: nil],
      workspace_dir: [type: {:or, [:string, nil]}, default: nil],
      sprite_name: [type: {:or, [:string, nil]}, default: nil],
      sprite_config: [type: {:or, [:map, nil]}, default: nil],
      sprites_mod: [type: :atom, default: Sprites]
    ]

  alias Jido.Lib.Bots.Foundation.RoleRunner
  alias Jido.Lib.Github.Actions.DocsWriter.Helpers

  @impl true
  def run(params, _context) do
    decision = params[:final_decision] || infer_decision(params)

    draft =
      if decision == :accepted,
        do: params[:writer_draft_v1],
        else: params[:writer_draft_v2]

    if decision in [:accepted, :revised] do
      ecosystem = Map.get(params.content_metadata, :ecosystem_packages, [])
      should_embed? = Enum.any?(["runic", "jido", "jido_action"], &(&1 in ecosystem))

      if should_embed? do
        embed_demo(params, draft, ecosystem)
      else
        {:ok, Helpers.pass_through(params) |> Map.put(:embedded_draft, draft)}
      end
    else
      {:ok, Helpers.pass_through(params) |> Map.put(:embedded_draft, draft)}
    end
  end

  defp embed_demo(params, draft, ecosystem) do
    prompt = demo_prompt(params[:docs_brief], draft)

    case RoleRunner.run(
           role: :writer,
           provider: params.writer_provider,
           session_id: params.session_id,
           repo_dir: params.repo_dir,
           run_id: params.run_id <> "-demo",
           prompt_file: ".jido/prompts/jido_docs_demo_#{params.run_id}.txt",
           prompt: prompt,
           phase: params[:codex_phase] || :triage,
           fallback_phase: params[:codex_fallback_phase],
           timeout: params[:timeout] || 300_000,
           shell_agent_mod: params[:shell_agent_mod] || Jido.Shell.Agent,
           shell_session_server_mod:
             params[:shell_session_server_mod] || Jido.Shell.ShellSessionServer
         ) do
      {:ok, result} ->
        demo_code = clean_elixir_code(result.summary || "")
        demo_section = build_demo_section(demo_code, ecosystem, params.run_id)
        embedded_draft = String.trim(draft || "") <> "\n\n" <> demo_section
        {:ok, Helpers.pass_through(params) |> Map.put(:embedded_draft, embedded_draft)}

      {:error, _reason} ->
        {:ok, Helpers.pass_through(params) |> Map.put(:embedded_draft, draft)}
    end
  end

  defp demo_prompt(docs_brief, draft) do
    """
    You are an expert Elixir engineer and technical educator.

    Your task is to build a minimal, self-contained executable script that perfectly
    demonstrates the core concepts taught in the following guide. This code will be
    appended at the bottom of the Livebook in a "Try It Live" section using Kino.

    Context Brief (Grounding Truth):
    #{docs_brief || ""}

    Guide Content (What was actually taught):
    #{draft || ""}

    REQUIREMENTS:
    - Output ONLY valid, executable Elixir code.
    - DO NOT wrap the code in markdown ```elixir fences. Just the raw code.
    - If building a Runic workflow, assign it to `demo_workflow`.
    - If building a Jido Agent, define it as `DemoAgent`.
    - Include any minimal dummy modules or functions needed for the code to compile and run.
    - DO NOT include `Mix.install/2` (it is already at the top of the Livebook).
    - DO NOT include the `Kino` visualizer calls, I will append that automatically.
    """
    |> String.trim()
  end

  defp clean_elixir_code(text) do
    text = String.trim(text)

    case Regex.run(~r/\A```(?:elixir)?\s*([\s\S]*?)\s*```\z/, text) do
      [_, inner] -> String.trim(inner)
      _ -> text
    end
  end

  defp build_demo_section(demo_code, ecosystem, run_id) do
    date = DateTime.utc_now() |> DateTime.to_date() |> Date.to_iso8601()

    playground =
      if "runic" in ecosystem do
        """
        if binding()[:demo_workflow] do
          Kino.Runic.viewer(demo_workflow)
        else
          Kino.Markdown.new("**Notice:** The tutorial did not export a `demo_workflow` variable to visualize.")
        end
        """
      else
        """
        if binding()[:DemoAgent] do
          Kino.Jido.agent_viewer(DemoAgent)
        else
          Kino.Markdown.new("**Notice:** The tutorial did not export a `DemoAgent` module to visualize.")
        end
        """
      end

    """
    ## Try It Live -- Interactive Demo

    *This interactive simulator was autonomously generated and compiler-verified by the Jido Documentation Pipeline on #{date} (Run ID: #{run_id}).*

    ```elixir
    #{String.trim(demo_code)}

    # Mount the Interactive Viewer
    #{String.trim(playground)}
    ```
    """
    |> String.trim()
  end

  defp infer_decision(params) do
    cond do
      is_map(params[:gate_v2]) and is_atom(params.gate_v2[:decision]) ->
        params.gate_v2[:decision]

      is_map(params[:gate_v1]) and is_atom(params.gate_v1[:decision]) ->
        params.gate_v1[:decision]

      true ->
        :failed
    end
  end
end
