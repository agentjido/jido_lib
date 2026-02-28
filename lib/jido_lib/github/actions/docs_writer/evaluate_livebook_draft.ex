defmodule Jido.Lib.Github.Actions.DocsWriter.EvaluateLivebookDraft do
  @moduledoc """
  Executes generated LiveMD code inside the Sprite to deterministically prove validity.

  Extracts all `elixir` code blocks from the writer's draft, writes them into
  a temporary `.exs` script, and runs them inside the sprite sandbox using
  `elixir <script>`. The resulting stdout/stderr trace is stored as
  `:execution_trace_v1` or `:execution_trace_v2` for the critic to evaluate.

  This is the **Compiler Gate**: if the generated code fails to compile or run,
  the critic will see the exact error and instruct the writer to fix it.
  """

  use Jido.Action,
    name: "docs_writer_evaluate_livebook",
    description: "Execute generated Livebook code in sprite sandbox for deterministic validation",
    compensation: [max_retries: 0],
    schema: [
      iteration: [type: :integer, required: true],
      run_id: [type: :string, required: true],
      session_id: [type: :string, required: true],
      repo_dir: [type: :string, required: true],
      writer_draft_v1: [type: {:or, [:string, nil]}, default: nil],
      writer_draft_v2: [type: {:or, [:string, nil]}, default: nil],
      shell_agent_mod: [type: :atom, default: Jido.Shell.Agent]
    ]

  alias Jido.Lib.Github.Actions.DocsWriter.Helpers
  alias Jido.Lib.Github.Helpers, as: GithubHelpers

  @eval_timeout_ms 120_000
  # Cap the execution trace so the critic prompt fits inside the Sprites API
  # payload limit.  Mix.install output dominates early lines — the actual
  # compilation/runtime error is always at the tail.
  @max_trace_bytes 4_096

  @impl true
  def run(params, _context) do
    draft =
      if params.iteration == 1,
        do: params[:writer_draft_v1],
        else: params[:writer_draft_v2]

    key =
      if params.iteration == 1,
        do: :execution_trace_v1,
        else: :execution_trace_v2

    if is_nil(draft) or String.trim(draft) == "" do
      {:ok,
       params
       |> Helpers.pass_through()
       |> Map.put(key, "No draft to execute.")}
    else
      code = extract_elixir_blocks(draft)

      if String.trim(code) == "" do
        {:ok,
         params
         |> Helpers.pass_through()
         |> Map.put(key, "No executable Elixir code blocks found in draft.")}
      else
        execute_code(params, code, key)
      end
    end
  end

  defp execute_code(params, code, key) do
    agent_mod = params[:shell_agent_mod] || Jido.Shell.Agent
    script_path = "/tmp/docs_eval_#{params.run_id}_v#{params.iteration}.exs"
    escaped_path = GithubHelpers.shell_escape_path(script_path)

    # If ExUnit tests are present but ExUnit.start isn't, add it
    code =
      if String.contains?(code, "ExUnit.Case") and not String.contains?(code, "ExUnit.start") do
        "ExUnit.start(autorun: false)\n\n" <> code <> "\n\nExUnit.run()"
      else
        code
      end

    write_cmd = "cat > #{escaped_path} << 'EOF_EVAL'\n#{code}\nEOF_EVAL"

    with {:ok, _} <-
           GithubHelpers.run_in_dir(agent_mod, params.session_id, params.repo_dir, write_cmd,
             timeout: 5_000
           ) do
      # Append `|| true` so the shell always exits 0, guaranteeing the
      # stdout/stderr output is captured even when elixir exits non-zero.
      # Error detection is handled by `has_error_indicators?/1` text analysis.
      exec_cmd = "elixir #{escaped_path} 2>&1 || true"

      trace =
        case GithubHelpers.run_in_dir(agent_mod, params.session_id, params.repo_dir, exec_cmd,
               timeout: @eval_timeout_ms
             ) do
          {:ok, stdout} ->
            if has_error_indicators?(stdout) do
              "BEAM Execution FAILED:\n\nCompiler/Runtime Error Trace:\n#{stdout}"
            else
              "BEAM Execution SUCCESS:\n#{stdout}"
            end

          {:error, reason} ->
            "SYSTEM ERROR: Could not run verification: #{inspect(reason)}"
        end

      {:ok,
       params
       |> Helpers.pass_through()
       |> Map.put(key, truncate_trace(trace))}
    else
      _ ->
        {:ok,
         params
         |> Helpers.pass_through()
         |> Map.put(key, "Failed to write evaluation script to Sprite.")}
    end
  end

  defp extract_elixir_blocks(markdown) do
    ~r/```elixir\n([\s\S]*?)\n```/s
    |> Regex.scan(markdown)
    |> Enum.map(fn [_, code] -> String.trim(code) end)
    |> Enum.join("\n\n# --- NEXT BLOCK ---\n\n")
  end

  defp has_error_indicators?(output) do
    # Match Elixir error patterns specifically.  The previous bare "failed" match
    # produced false positives on normal Jido runtime log lines like
    # "[warning] Runnable failed …" that appear during successful execution.
    String.contains?(output, "(CompileError)") or
      String.contains?(output, "(UndefinedFunctionError)") or
      String.contains?(output, "(ArgumentError)") or
      String.contains?(output, "(RuntimeError)") or
      String.contains?(output, "(FunctionClauseError)") or
      String.contains?(output, "** (")
  end

  # Keep only the tail of the trace when it exceeds the byte limit.
  # Mix.install dependency resolution output (packages, compilation logs)
  # dominates the beginning; the actual error is always at the end.
  defp truncate_trace(trace) when byte_size(trace) <= @max_trace_bytes, do: trace

  defp truncate_trace(trace) do
    tail = binary_part(trace, byte_size(trace) - @max_trace_bytes, @max_trace_bytes)
    "[… truncated #{byte_size(trace) - @max_trace_bytes} bytes of Mix.install output …]\n" <> tail
  end
end
