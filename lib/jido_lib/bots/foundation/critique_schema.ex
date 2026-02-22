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

  @spec from_output(String.t() | nil) :: {:ok, t()} | {:error, term()}
  def from_output(payload) when is_binary(payload) do
    payload
    |> extract_candidate_maps()
    |> select_consistent_candidate()
  end

  def from_output(_payload), do: {:error, :empty_critique_output}

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
    markers = verdict_markers(text)

    case resolve_marker_verdict(markers) do
      :unknown -> infer_verdict_from_keywords(text)
      verdict -> verdict
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

  defp extract_candidate_maps(payload) when is_binary(payload) do
    payload
    |> gather_candidate_payloads()
    |> Enum.flat_map(&decode_payload_candidates/1)
    |> Enum.uniq()
  end

  defp gather_candidate_payloads(payload) when is_binary(payload) do
    [payload]
    |> Kernel.++(String.split(payload, "\n", trim: true))
    |> Kernel.++(extract_code_fence_blocks(payload))
    |> Kernel.++(extract_json_object_fragments(payload))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp decode_payload_candidates(payload) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, decoded} -> collect_critique_maps(decoded)
      {:error, _} -> []
    end
  end

  defp collect_critique_maps(%{} = map) do
    direct = if has_verdict_key?(map), do: [map], else: []
    nested = map |> Map.values() |> Enum.flat_map(&collect_critique_maps/1)
    direct ++ nested
  end

  defp collect_critique_maps(values) when is_list(values) do
    Enum.flat_map(values, &collect_critique_maps/1)
  end

  defp collect_critique_maps(value) when is_binary(value) do
    value
    |> gather_candidate_payloads()
    |> Enum.flat_map(&decode_payload_candidates/1)
  end

  defp collect_critique_maps(_value), do: []

  defp has_verdict_key?(map) when is_map(map) do
    Map.has_key?(map, :verdict) or Map.has_key?(map, "verdict")
  end

  defp select_consistent_candidate([]), do: {:error, :no_critique_payload}

  defp select_consistent_candidate(candidates) when is_list(candidates) do
    critiques =
      Enum.reduce(candidates, [], fn candidate, acc ->
        case new(candidate) do
          {:ok, critique} -> [critique | acc]
          {:error, _} -> acc
        end
      end)
      |> Enum.reverse()

    case critiques do
      [] ->
        {:error, :invalid_critique_payload}

      values ->
        verdicts = values |> Enum.map(& &1.verdict) |> Enum.uniq()

        case verdicts do
          [single] ->
            {:ok, values |> Enum.reverse() |> Enum.find(&(&1.verdict == single))}

          [] ->
            {:error, :invalid_critique_payload}

          _ ->
            {:error, {:ambiguous_critique_verdicts, verdicts}}
        end
    end
  end

  defp extract_code_fence_blocks(text) when is_binary(text) do
    Regex.scan(~r/```(?:json)?\s*([\s\S]*?)\s*```/i, text, capture: :all_but_first)
    |> Enum.map(fn [block] -> block end)
  end

  defp extract_json_object_fragments(text) when is_binary(text) do
    chars = String.to_charlist(text)
    state = %{depth: 0, in_string: false, escaped: false, buffer: [], objects: []}

    chars
    |> Enum.reduce(state, &scan_json_char/2)
    |> Map.get(:objects)
    |> Enum.reverse()
    |> Enum.filter(&String.contains?(&1, "\"verdict\""))
  end

  defp scan_json_char(char, state) when state.depth == 0 do
    if char == ?{ do
      %{state | depth: 1, in_string: false, escaped: false, buffer: [char]}
    else
      state
    end
  end

  defp scan_json_char(char, state) do
    buffer = [char | state.buffer]
    {next_in_string, next_escaped, next_depth} = next_json_scan_state(state, char)
    finalize_json_scan(state, buffer, next_in_string, next_escaped, next_depth)
  end

  defp verdict_markers(text) when is_binary(text) do
    %{
      accept: contains_any?(text, ["\"verdict\":\"accept\"", "\"verdict\": \"accept\""]),
      revise: contains_any?(text, ["\"verdict\":\"revise\"", "\"verdict\": \"revise\""]),
      reject: contains_any?(text, ["\"verdict\":\"reject\"", "\"verdict\": \"reject\""])
    }
  end

  defp resolve_marker_verdict(%{accept: true, revise: false, reject: false}), do: :accept
  defp resolve_marker_verdict(%{accept: false, revise: false, reject: true}), do: :reject
  defp resolve_marker_verdict(%{accept: false, revise: true, reject: false}), do: :revise
  defp resolve_marker_verdict(%{accept: false, revise: false, reject: false}), do: :unknown
  defp resolve_marker_verdict(_), do: :revise

  defp infer_verdict_from_keywords(text) when is_binary(text) do
    cond do
      contains_any?(text, ["reject", "block"]) -> :reject
      contains_any?(text, ["revise", "needs revision", "needs_revision"]) -> :revise
      true -> :revise
    end
  end

  defp next_json_scan_state(%{in_string: true} = state, char) do
    next_json_scan_state_in_string(state, char)
  end

  defp next_json_scan_state(%{in_string: false} = state, char) do
    next_json_scan_state_outside_string(state, char)
  end

  defp next_json_scan_state_in_string(%{escaped: true, depth: depth}, _char),
    do: {true, false, depth}

  defp next_json_scan_state_in_string(%{depth: depth}, ?\\), do: {true, true, depth}
  defp next_json_scan_state_in_string(%{depth: depth}, ?"), do: {false, false, depth}
  defp next_json_scan_state_in_string(%{depth: depth}, _char), do: {true, false, depth}

  defp next_json_scan_state_outside_string(%{depth: depth}, ?"), do: {true, false, depth}
  defp next_json_scan_state_outside_string(%{depth: depth}, ?{), do: {false, false, depth + 1}

  defp next_json_scan_state_outside_string(%{depth: depth}, ?}),
    do: {false, false, max(depth - 1, 0)}

  defp next_json_scan_state_outside_string(%{depth: depth}, _char), do: {false, false, depth}

  defp finalize_json_scan(state, buffer, _next_in_string, _next_escaped, 0) do
    object = buffer |> Enum.reverse() |> to_string()

    %{
      state
      | depth: 0,
        in_string: false,
        escaped: false,
        buffer: [],
        objects: [object | state.objects]
    }
  end

  defp finalize_json_scan(state, buffer, next_in_string, next_escaped, next_depth) do
    %{
      state
      | depth: next_depth,
        in_string: next_in_string,
        escaped: next_escaped,
        buffer: buffer
    }
  end
end
