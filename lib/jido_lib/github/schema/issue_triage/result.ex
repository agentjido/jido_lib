defmodule Jido.Lib.Github.Schema.IssueTriage.Result do
  @moduledoc """
  Validated output struct for a GitHub issue triage run.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              status: Zoi.atom(),
              run_id: Zoi.string(),
              provider: Zoi.atom() |> Zoi.nullish(),
              owner: Zoi.string(),
              repo: Zoi.string(),
              issue_number: Zoi.integer(),
              message: Zoi.string() |> Zoi.nullish(),
              investigation: Zoi.string() |> Zoi.nullish(),
              investigation_status: Zoi.atom() |> Zoi.nullish(),
              investigation_error: Zoi.string() |> Zoi.nullish(),
              agent_status: Zoi.atom() |> Zoi.nullish(),
              agent_summary: Zoi.string() |> Zoi.nullish(),
              agent_error: Zoi.string() |> Zoi.nullish(),
              comment_posted: Zoi.boolean() |> Zoi.nullish(),
              comment_url: Zoi.string() |> Zoi.nullish(),
              comment_error: Zoi.string() |> Zoi.nullish(),
              sprite_name: Zoi.string() |> Zoi.nullish(),
              session_id: Zoi.string() |> Zoi.nullish(),
              workspace_dir: Zoi.string() |> Zoi.nullish(),
              teardown_verified: Zoi.boolean() |> Zoi.nullish(),
              teardown_attempts: Zoi.integer() |> Zoi.nullish(),
              warnings: Zoi.array(Zoi.string()) |> Zoi.nullish(),
              runtime_checks: Zoi.map() |> Zoi.nullish()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for this struct."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Builds a new result from a map, validating with Zoi."
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs), do: Zoi.parse(@schema, attrs)

  @doc "Like `new/1` but raises on validation errors."
  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, value} ->
        value

      {:error, reason} ->
        raise ArgumentError, "Invalid #{inspect(__MODULE__)}: #{inspect(reason)}"
    end
  end
end
