defmodule Jido.LibTest do
  use ExUnit.Case
  doctest Jido.Lib

  test "returns version" do
    assert is_binary(Jido.Lib.version())
  end
end
