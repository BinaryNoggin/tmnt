defmodule TmntTest do
  use ExUnit.Case
  doctest Tmnt

  test "greets the world" do
    assert Tmnt.hello() == :world
  end
end
