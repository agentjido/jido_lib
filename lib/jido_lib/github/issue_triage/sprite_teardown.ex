defmodule Jido.Lib.Github.IssueTriage.SpriteTeardown do
  @moduledoc false

  @type teardown_result :: %{
          teardown_verified: boolean(),
          teardown_attempts: pos_integer(),
          warnings: [String.t()] | nil
        }

  @spec teardown(String.t(), String.t() | nil, module(), map() | nil, keyword()) ::
          teardown_result()
  def teardown(session_id, sprite_name, stop_mod, sprite_config, opts \\ [])
      when is_binary(session_id) and is_atom(stop_mod) do
    Jido.Shell.SpriteLifecycle.teardown(session_id,
      sprite_name: sprite_name,
      stop_mod: stop_mod,
      sprite_config: sprite_config,
      sprites_mod: Keyword.get(opts, :sprites_mod, Sprites)
    )
  end
end
