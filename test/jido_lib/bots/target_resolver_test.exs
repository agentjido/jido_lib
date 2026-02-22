defmodule Jido.Lib.Bots.TargetResolverTest do
  use ExUnit.Case, async: true

  alias Jido.Lib.Bots.TargetResolver

  test "resolves local path targets" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "target-resolver-local-#{System.unique_integer([:positive])}")

    :ok = File.mkdir_p(tmp_dir)

    assert {:ok, info} = TargetResolver.resolve(tmp_dir)
    assert info.kind == :local
    assert info.path == Path.expand(tmp_dir)
    assert info.slug == nil
  end

  test "resolves owner/repo slug targets with provided clone dir" do
    clone_dir =
      Path.join(System.tmp_dir!(), "target-resolver-clone-#{System.unique_integer([:positive])}")

    assert {:ok, info} = TargetResolver.resolve("agentjido/jido_lib", clone_dir: clone_dir)
    assert info.kind == :github
    assert info.owner == "agentjido"
    assert info.repo == "jido_lib"
    assert info.path == clone_dir
    assert info.slug == "agentjido/jido_lib"
  end

  test "rejects invalid targets" do
    assert {:error, {:invalid_target, "not a target"}} = TargetResolver.resolve("not a target")
  end
end
