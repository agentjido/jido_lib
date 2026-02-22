defmodule Jido.Lib.Bots.Foundation.ArtifactStore do
  @moduledoc """
  Stores workflow artifacts under `.jido/runs/<run_id>/` via `Jido.VFS`.
  """

  alias Jido.Lib.Github.Helpers

  @type t :: %__MODULE__{
          run_id: String.t(),
          filesystem: Jido.VFS.filesystem(),
          base_path: String.t(),
          adapter: :sprite | :local
        }

  defstruct [:run_id, :filesystem, :base_path, :adapter]

  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts) do
    run_id = normalize_run_id(Keyword.get(opts, :run_id))
    base_path = Path.join([".jido", "runs", run_id])

    with {:ok, filesystem, adapter} <- configure_filesystem(opts, run_id),
         :ok <- ensure_directory(filesystem, base_path) do
      {:ok,
       %__MODULE__{
         run_id: run_id,
         filesystem: filesystem,
         base_path: base_path,
         adapter: adapter
       }}
    end
  end

  @spec new!(keyword()) :: t()
  def new!(opts) when is_list(opts) do
    case new(opts) do
      {:ok, store} -> store
      {:error, reason} -> raise ArgumentError, "artifact store init failed: #{inspect(reason)}"
    end
  end

  @spec path_for(t(), String.t()) :: String.t()
  def path_for(%__MODULE__{} = store, relative) when is_binary(relative) do
    Path.join(store.base_path, relative)
  end

  @spec write_text(t(), String.t(), iodata()) :: {:ok, map()} | {:error, term()}
  def write_text(%__MODULE__{} = store, relative_path, content)
      when is_binary(relative_path) do
    full_path = path_for(store, relative_path)

    with :ok <- ensure_parent_directory(store.filesystem, full_path),
         :ok <- Jido.VFS.write(store.filesystem, full_path, content) do
      {:ok, artifact_meta(full_path, IO.iodata_to_binary(content))}
    end
  end

  @spec write_json(t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def write_json(%__MODULE__{} = store, relative_path, payload)
      when is_binary(relative_path) and is_map(payload) do
    encoded = Jason.encode!(payload, pretty: true)
    write_text(store, relative_path, encoded)
  end

  @spec read_text(t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def read_text(%__MODULE__{} = store, relative_path) when is_binary(relative_path) do
    path = path_for(store, relative_path)

    case Jido.VFS.read(store.filesystem, path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec read_json(t(), String.t()) :: {:ok, map()} | {:error, term()}
  def read_json(%__MODULE__{} = store, relative_path) when is_binary(relative_path) do
    case read_text(store, relative_path) do
      {:ok, content} -> Jason.decode(content)
      {:error, reason} -> {:error, reason}
    end
  end

  @spec base_prefix(String.t()) :: String.t()
  def base_prefix(run_id) when is_binary(run_id), do: Path.join([".jido", "runs", run_id])

  defp configure_filesystem(opts, run_id) do
    sprite_name = keyword_get(opts, :sprite_name)
    sprite_config = keyword_get(opts, :sprite_config, %{})
    sprites_mod = keyword_get(opts, :sprites_mod, Sprites)
    token = sprite_token(sprite_config)

    root_dir =
      normalize_root_dir(keyword_get(opts, :repo_dir) || keyword_get(opts, :workspace_dir))

    if sprite_compatible?(sprites_mod, sprite_name, token) do
      case safe_configure_loaded(Jido.VFS.Adapter.Sprite,
             sprite_name: sprite_name,
             token: token,
             root: root_dir,
             client: sprites_mod,
             probe_commands: false
           ) do
        {:ok, fs} -> {:ok, fs, :sprite}
        {:error, _reason} -> configure_local_fallback(opts, run_id)
      end
    else
      configure_local_fallback(opts, run_id)
    end
  end

  defp configure_local_fallback(opts, run_id) do
    local_prefix =
      [
        keyword_get(opts, :local_prefix),
        keyword_get(opts, :repo_dir),
        keyword_get(opts, :workspace_dir)
      ]
      |> Enum.find(&valid_host_directory?/1)
      |> case do
        dir when is_binary(dir) -> dir
        _ -> Path.join([System.tmp_dir!(), "jido-lib-artifacts", run_id])
      end

    case safe_configure_loaded(Jido.VFS.Adapter.Local, prefix: local_prefix) do
      {:ok, fs} -> {:ok, fs, :local}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_directory(filesystem, path) do
    Jido.VFS.create_directory(filesystem, ensure_dir(path), recursive: true)
  end

  defp ensure_parent_directory(filesystem, path) do
    path
    |> Path.dirname()
    |> case do
      "." -> :ok
      dir -> ensure_directory(filesystem, dir)
    end
  end

  defp ensure_dir(path) when is_binary(path) do
    if String.ends_with?(path, "/"), do: path, else: path <> "/"
  end

  defp normalize_root_dir(dir) when is_binary(dir) and dir != "", do: dir
  defp normalize_root_dir(_), do: "/"

  defp valid_host_directory?(path) when is_binary(path) do
    path != "" and File.dir?(path)
  end

  defp valid_host_directory?(_), do: false

  defp sprite_compatible?(client, sprite_name, token)
       when is_atom(client) and is_binary(sprite_name) and is_binary(token) do
    function_exported?(client, :new, 2) and
      function_exported?(client, :sprite, 2) and
      function_exported?(client, :cmd, 4)
  end

  defp sprite_compatible?(_client, _sprite_name, _token), do: false

  defp sprite_token(%{} = sprite_config) do
    Helpers.map_get(sprite_config, :token) || System.get_env("SPRITES_TOKEN")
  end

  defp sprite_token(_), do: System.get_env("SPRITES_TOKEN")

  defp normalize_run_id(run_id) when is_binary(run_id) and run_id != "", do: run_id

  defp normalize_run_id(_run_id) do
    :crypto.strong_rand_bytes(6)
    |> Base.encode16(case: :lower)
  end

  defp safe_configure_loaded(adapter, opts) when is_atom(adapter) and is_list(opts) do
    case Code.ensure_loaded(adapter) do
      {:module, _} -> Jido.VFS.safe_configure(adapter, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  defp keyword_get(opts, key, default \\ nil) when is_list(opts) and is_atom(key) do
    Keyword.get(opts, key, default)
  end

  defp artifact_meta(path, content) when is_binary(path) and is_binary(content) do
    %{
      path: path,
      bytes: byte_size(content),
      sha256: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
    }
  end
end
