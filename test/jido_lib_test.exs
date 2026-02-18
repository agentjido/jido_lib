defmodule JidoLibTest do
  use ExUnit.Case
  doctest JidoLib

  test "greets the world" do
    assert JidoLib.hello() == :world
  end
end
