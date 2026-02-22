defmodule Jido.Lib.Bots.TargetResolver do
  @moduledoc """
  Resolves bot targets from local paths or GitHub owner/repo identifiers.
  """

  @github_slug ~r/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/

  @spec resolve(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def resolve(target, opts \\ []) when is_binary(target) and is_list(opts) do
    target = String.trim(target)

    cond do
      target == "" ->
        {:error, :empty_target}

      File.dir?(target) ->
        {:ok,
         %{
           kind: :local,
           target: target,
           path: Path.expand(target),
           owner: nil,
           repo: nil,
           slug: nil
         }}

      Regex.match?(@github_slug, target) ->
        [owner, repo] = String.split(target, "/", parts: 2)

        clone_dir =
          Keyword.get(opts, :clone_dir, Path.join(System.tmp_dir!(), "jido-bot-#{owner}-#{repo}"))

        {:ok,
         %{
           kind: :github,
           target: target,
           path: clone_dir,
           owner: owner,
           repo: repo,
           slug: target
         }}

      true ->
        {:error, {:invalid_target, target}}
    end
  end
end
