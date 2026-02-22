defmodule Jido.Lib.Bots.Foundation.CritiqueSchema do
  @moduledoc """
  Canonical normalized critique payload for writer/critic loops.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              verdict: Zoi.enum([:accept, :revise, :reject]),
              severity: Zoi.enum([:low, :medium, :high, :critical]) |> Zoi.default(:medium),
              findings: Zoi.array(Zoi.map()) |> Zoi.default([]),
              revision_instructions: Zoi.string() |> Zoi.default(""),
              confidence: Zoi.float() |> Zoi.default(0.5)
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
    attrs
    |> normalize_fields()
    |> then(&Zoi.parse(@schema, &1))
  end

  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs) do
    case new(attrs) do
      {:ok, critique} -> critique
      {:error, reason} -> raise ArgumentError, "invalid critique payload: #{inspect(reason)}"
    end
  end

  @spec from_json(String.t()) :: {:ok, t()} | {:error, term()}
  def from_json(payload) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, decoded} -> new(decoded)
      {:error, reason} -> {:error, reason}
    end
  end

  @spec from_text(String.t() | nil) :: t()
  def from_text(payload) when is_binary(payload) do
    case from_json(payload) do
      {:ok, critique} -> critique
      {:error, _} -> infer_from_text(payload)
    end
  end

  def from_text(_payload), do: infer_from_text("")

  @spec to_map(t() | map()) :: map()
  def to_map(%__MODULE__{} = critique), do: Map.from_struct(critique)
  def to_map(%{} = critique), do: critique

  defp normalize_fields(attrs) do
    %{
      verdict: attrs |> get_value(:verdict, "verdict", :revise) |> normalize_verdict(),
      severity: attrs |> get_value(:severity, "severity", :medium) |> normalize_severity(),
      findings: attrs |> get_value(:findings, "findings", []) |> normalize_findings(),
      revision_instructions:
        attrs
        |> get_value(:revision_instructions, "revision_instructions", "")
        |> normalize_revision_instructions(),
      confidence: attrs |> get_value(:confidence, "confidence", 0.5) |> normalize_confidence()
    }
  end

  defp get_value(map, atom_key, string_key, default) when is_map(map) do
    Map.get(map, atom_key, Map.get(map, string_key, default))
  end

  defp normalize_verdict(:accept), do: :accept
  defp normalize_verdict(:revise), do: :revise
  defp normalize_verdict(:reject), do: :reject
  defp normalize_verdict("accept"), do: :accept
  defp normalize_verdict("approved"), do: :accept
  defp normalize_verdict("revise"), do: :revise
  defp normalize_verdict("needs_revision"), do: :revise
  defp normalize_verdict("reject"), do: :reject
  defp normalize_verdict("blocked"), do: :reject
  defp normalize_verdict(_), do: :revise

  defp normalize_severity(:low), do: :low
  defp normalize_severity(:medium), do: :medium
  defp normalize_severity(:high), do: :high
  defp normalize_severity(:critical), do: :critical
  defp normalize_severity("low"), do: :low
  defp normalize_severity("medium"), do: :medium
  defp normalize_severity("high"), do: :high
  defp normalize_severity("critical"), do: :critical
  defp normalize_severity(_), do: :medium

  defp normalize_findings(value) when is_list(value), do: value
  defp normalize_findings(%{} = value), do: [value]
  defp normalize_findings(_), do: []

  defp normalize_revision_instructions(value) when is_binary(value), do: value
  defp normalize_revision_instructions(value), do: inspect(value)

  defp normalize_confidence(value) when is_float(value), do: clamp_confidence(value)
  defp normalize_confidence(value) when is_integer(value), do: clamp_confidence(value / 1.0)

  defp normalize_confidence(value) when is_binary(value) do
    case Float.parse(value) do
      {parsed, _rest} -> clamp_confidence(parsed)
      :error -> 0.5
    end
  end

  defp normalize_confidence(_), do: 0.5

  defp infer_from_text(text) when is_binary(text) do
    lowered = String.downcase(text)
    verdict = infer_verdict(lowered)
    severity = infer_severity(lowered)
    findings = infer_findings(text)

    new!(%{
      verdict: verdict,
      severity: severity,
      findings: findings,
      revision_instructions: if(verdict == :revise, do: text, else: ""),
      confidence: 0.5
    })
  end

  defp clamp_confidence(value) when value < 0.0, do: 0.0
  defp clamp_confidence(value) when value > 1.0, do: 1.0
  defp clamp_confidence(value), do: value

  defp infer_verdict(text) when is_binary(text) do
    cond do
      String.contains?(text, "\"verdict\":\"accept\"") ->
        :accept

      String.contains?(text, "\"verdict\":\"reject\"") ->
        :reject

      contains_any?(text, ["reject", "block"]) ->
        :reject

      contains_any?(text, ["approve", "accept"]) ->
        :accept

      true ->
        :revise
    end
  end

  defp infer_severity(text) when is_binary(text) do
    cond do
      String.contains?(text, "critical") -> :critical
      String.contains?(text, "high") -> :high
      String.contains?(text, "low") -> :low
      true -> :medium
    end
  end

  defp infer_findings(text) when is_binary(text) do
    if String.trim(text) == "" do
      []
    else
      [%{message: String.slice(text, 0, 500)}]
    end
  end

  defp contains_any?(text, terms) when is_binary(text) and is_list(terms) do
    Enum.any?(terms, &String.contains?(text, &1))
  end
end
