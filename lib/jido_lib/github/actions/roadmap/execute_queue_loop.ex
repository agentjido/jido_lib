defmodule Jido.Lib.Github.Actions.Roadmap.ExecuteQueueLoop do
  @moduledoc """
  Executes roadmap queue items one-by-one with explicit dependency blocking.
  """

  use Jido.Action,
    name: "roadmap_execute_queue_loop",
    description: "Execute roadmap queue loop",
    compensation: [max_retries: 0],
    schema: [
      run_id: [type: :string, required: true],
      repo_dir: [type: :string, required: true],
      queue: [type: {:list, :map}, default: []],
      include_completed: [type: :boolean, default: false],
      apply: [type: :boolean, default: false]
    ]

  alias Jido.Lib.Github.Actions.Common.MutationGuard
  alias Jido.Lib.Github.Actions.Roadmap.Helpers

  @state_file ".jido/roadmap_state.json"

  @impl true
  def run(params, _context) do
    state_path = Path.join(params.repo_dir, @state_file)
    previous_state = read_state(state_path)
    completed_state = Map.get(previous_state, "items", %{})

    {queue_results, next_state} =
      Enum.reduce(params.queue, {[], completed_state}, fn item, {acc, state} ->
        result = execute_item(item, state, params)
        updated_state = Map.put(state, item_id(item), Atom.to_string(result.status))
        {[result | acc], updated_state}
      end)

    state_payload = %{
      "run_id" => params.run_id,
      "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "items" => next_state
    }

    persist_state!(state_path, state_payload)

    queue_results = Enum.reverse(queue_results)
    summary = summarize(queue_results)

    {:ok,
     Helpers.pass_through(params)
     |> Map.put(:queue_results, queue_results)
     |> Map.put(:state_file, state_path)
     |> Map.put(:summary, summary)
     |> Map.put(:artifacts, [state_path])}
  end

  defp execute_item(item, state, params) do
    id = item_id(item)
    deps = Map.get(item, :dependencies, []) || []

    cond do
      state[id] == "completed" and params[:include_completed] != true ->
        %{
          id: id,
          title: Map.get(item, :title, ""),
          status: :skipped,
          reason: :already_completed
        }

      blocked_by = blocked_dependencies(deps, state) ->
        %{
          id: id,
          title: Map.get(item, :title, ""),
          status: :blocked,
          blocked_by: blocked_by
        }

      params[:apply] == true and MutationGuard.mutation_allowed?(params) ->
        execute_mutating_item(item, params)

      true ->
        %{
          id: id,
          title: Map.get(item, :title, ""),
          status: :planned,
          summary: "dry-run"
        }
    end
  end

  defp execute_mutating_item(item, params) do
    id = item_id(item)
    file_name = id |> String.downcase() |> String.replace(~r/[^a-z0-9_-]/, "-")
    story_dir = Path.join(params.repo_dir, ".jido/roadmap_items")
    story_file = Path.join(story_dir, "#{file_name}.md")
    :ok = File.mkdir_p(story_dir)

    content = """
    # #{id}

    Title: #{Map.get(item, :title, "")}
    Source: #{Map.get(item, :source, :unknown)}
    Run: #{params.run_id}
    """

    case File.write(story_file, content) do
      :ok ->
        %{
          id: id,
          title: Map.get(item, :title, ""),
          status: :completed,
          artifact: story_file
        }

      {:error, reason} ->
        %{
          id: id,
          title: Map.get(item, :title, ""),
          status: :failed,
          error: inspect(reason)
        }
    end
  end

  defp blocked_dependencies(deps, state) when is_list(deps) and is_map(state) do
    deps
    |> Enum.reject(fn dep -> Map.get(state, dep) in ["completed", "planned"] end)
    |> case do
      [] -> nil
      blocked -> blocked
    end
  end

  defp blocked_dependencies(_deps, _state), do: nil

  defp read_state(path) when is_binary(path) do
    with {:ok, content} <- File.read(path),
         {:ok, decoded} <- Jason.decode(content),
         true <- is_map(decoded) do
      decoded
    else
      _ -> %{"items" => %{}}
    end
  end

  defp persist_state!(path, state_payload) do
    :ok = File.mkdir_p(Path.dirname(path))
    :ok = File.write!(path, Jason.encode!(state_payload, pretty: true))
  end

  defp item_id(item), do: Map.get(item, :id, "unknown-item")

  defp summarize(queue_results) when is_list(queue_results) do
    %{
      total: length(queue_results),
      completed: Enum.count(queue_results, &(&1.status == :completed)),
      planned: Enum.count(queue_results, &(&1.status == :planned)),
      skipped: Enum.count(queue_results, &(&1.status == :skipped)),
      blocked: Enum.count(queue_results, &(&1.status == :blocked)),
      failed: Enum.count(queue_results, &(&1.status == :failed))
    }
  end
end
