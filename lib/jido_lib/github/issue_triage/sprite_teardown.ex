defmodule Jido.Lib.Github.IssueTriage.SpriteTeardown do
  @moduledoc false

  @retry_backoffs_ms [0, 1_000, 3_000]

  @type teardown_result :: %{
          teardown_verified: boolean(),
          teardown_attempts: pos_integer(),
          warnings: [String.t()] | nil
        }

  @spec teardown(String.t(), String.t() | nil, module(), map() | nil, keyword()) ::
          teardown_result()
  def teardown(session_id, sprite_name, stop_mod, sprite_config, opts \\ [])
      when is_binary(session_id) and is_atom(stop_mod) do
    sprites_mod = Keyword.get(opts, :sprites_mod, Sprites)
    client = build_client(sprite_config, sprites_mod)

    Enum.with_index(@retry_backoffs_ms, 1)
    |> Enum.reduce_while(%{warnings: []}, fn {backoff_ms, attempt}, acc ->
      maybe_sleep(backoff_ms)

      warnings =
        acc.warnings
        |> maybe_add_warning(stop_session(stop_mod, session_id), "session_stop")

      case verify_and_destroy(sprite_name, client, sprites_mod, warnings) do
        {:verified, attempt_warnings} ->
          {:halt,
           %{
             teardown_verified: true,
             teardown_attempts: attempt,
             warnings: normalize_warnings(attempt_warnings)
           }}

        {:not_verified, attempt_warnings} ->
          {:cont, %{warnings: attempt_warnings}}
      end
    end)
    |> case do
      %{teardown_verified: _} = done ->
        done

      %{warnings: warnings} ->
        %{
          teardown_verified: false,
          teardown_attempts: length(@retry_backoffs_ms),
          warnings:
            normalize_warnings([
              "sprite teardown not verified after retries"
              | warnings
            ])
        }
    end
  end

  defp maybe_sleep(ms) when is_integer(ms) and ms > 0, do: Process.sleep(ms)
  defp maybe_sleep(_), do: :ok

  defp stop_session(mod, session_id) do
    if supports?(mod, :stop, 1) do
      mod.stop(session_id)
    else
      Jido.Shell.Agent.stop(session_id)
    end
  end

  defp verify_and_destroy(sprite_name, client, sprites_mod, warnings) do
    case verify_absent(sprite_name, client, sprites_mod) do
      :absent ->
        {:verified, warnings}

      :present ->
        destroy_result = destroy_sprite(sprite_name, client, sprites_mod)

        warnings =
          warnings
          |> maybe_add_warning(destroy_result, "sprite_destroy")

        case verify_absent(sprite_name, client, sprites_mod) do
          :absent -> {:verified, warnings}
          :present -> {:not_verified, warnings}
          {:error, reason} -> {:not_verified, add_warning(warnings, verification_warning(reason))}
        end

      {:error, reason} ->
        {:not_verified, add_warning(warnings, verification_warning(reason))}
    end
  end

  defp verify_absent(nil, _client, _sprites_mod), do: {:error, :missing_sprite_name}
  defp verify_absent("", _client, _sprites_mod), do: {:error, :missing_sprite_name}
  defp verify_absent(_sprite_name, nil, _sprites_mod), do: {:error, :missing_sprites_client}

  defp verify_absent(sprite_name, client, sprites_mod) do
    if supports?(sprites_mod, :get_sprite, 2) do
      case sprites_mod.get_sprite(client, sprite_name) do
        {:ok, _sprite} ->
          :present

        {:error, reason} ->
          if not_found_reason?(reason), do: :absent, else: {:error, reason}
      end
    else
      {:error, :missing_get_sprite_api}
    end
  end

  defp destroy_sprite(nil, _client, _sprites_mod), do: {:error, :missing_sprite_name}
  defp destroy_sprite("", _client, _sprites_mod), do: {:error, :missing_sprite_name}
  defp destroy_sprite(_sprite_name, nil, _sprites_mod), do: {:error, :missing_sprites_client}

  defp destroy_sprite(sprite_name, client, sprites_mod) do
    with true <- supports?(sprites_mod, :sprite, 2),
         true <- supports?(sprites_mod, :destroy, 1) do
      sprite = sprites_mod.sprite(client, sprite_name)

      case sprites_mod.destroy(sprite) do
        :ok -> :ok
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
        other -> {:error, {:unexpected_destroy_result, other}}
      end
    else
      _ -> {:error, :missing_destroy_api}
    end
  end

  defp build_client(sprite_config, sprites_mod)
       when is_map(sprite_config) and is_atom(sprites_mod) do
    token = sprite_opt(sprite_config, :token)

    if is_binary(token) and String.trim(token) != "" and supports?(sprites_mod, :new, 2) do
      base_url = sprite_opt(sprite_config, :base_url)

      opts =
        if is_binary(base_url) and String.trim(base_url) != "", do: [base_url: base_url], else: []

      sprites_mod.new(token, opts)
    else
      nil
    end
  end

  defp build_client(_, _), do: nil

  defp supports?(mod, fun, arity)
       when is_atom(mod) and is_atom(fun) and is_integer(arity) and arity >= 0 do
    Code.ensure_loaded?(mod) and function_exported?(mod, fun, arity)
  end

  defp not_found_reason?(%{status: 404}), do: true
  defp not_found_reason?({:http_error, 404, _}), do: true
  defp not_found_reason?({:error, %{status: 404}}), do: true
  defp not_found_reason?(:not_found), do: true
  defp not_found_reason?({:not_found, _}), do: true

  defp not_found_reason?(reason) when is_binary(reason) do
    down = String.downcase(reason)
    String.contains?(down, "404") or String.contains?(down, "not found")
  end

  defp not_found_reason?(reason), do: String.contains?(inspect(reason), "404")

  defp maybe_add_warning(warnings, :ok, _prefix), do: warnings
  defp maybe_add_warning(warnings, {:ok, _}, _prefix), do: warnings

  defp maybe_add_warning(warnings, reason, prefix) do
    add_warning(warnings, "#{prefix}_failed=#{inspect(reason)}")
  end

  defp verification_warning(reason), do: "sprite_verification_failed=#{inspect(reason)}"

  defp add_warning(warnings, warning) when is_list(warnings) and is_binary(warning) do
    [warning | warnings]
  end

  defp normalize_warnings([]), do: nil

  defp normalize_warnings(warnings) when is_list(warnings) do
    warnings
    |> Enum.reverse()
    |> Enum.uniq()
  end

  defp sprite_opt(config, key) when is_map(config) do
    Map.get(config, key, Map.get(config, Atom.to_string(key)))
  end
end
