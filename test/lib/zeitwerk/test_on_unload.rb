# frozen_string_literal: true

require "test_helper"

class TestOnUnload < LoaderTest
  test "on_unload checks its argument type" do
    assert_raises(TypeError, "on_unload only accepts strings") do
       loader.on_unload(:X) {}
    end

    assert_raises(TypeError, "on_unload only accepts strings") do
      loader.on_unload(Object) {}
    end
  end

  test "multiple on_unload on cpaths are called in order of definition" do
    with_setup([["x.rb", "X = 1"]]) do
      x = []
      loader.on_unload("X") { x << 1 }
      loader.on_unload("X") { x << 2 }

      assert X
      loader.reload

      assert_equal [1, 2], x
    end
  end

  test "on_unload blocks get the expected arguments passed" do
    with_setup([["x.rb", "X = 1"]]) do
      args = []; loader.on_unload("X") { |*a| args = a }

      assert X
      loader.reload

      assert_equal 1, args[0]
      assert_abspath "x.rb", args[1]
    end
  end

  test "on_unload on cpaths are not called for other constants" do
    files = [
      ["x.rb", "X = 1"],
      ["y.rb", "Y = 1"]
    ]
    with_setup(files) do
      on_unload_for_Y = false
      loader.on_unload("Y") { on_unload_for_Y = true }

      assert X
      loader.reload

      assert !on_unload_for_Y
    end
  end

  test "on_unload for :ANY is called with the expected arguments" do
    with_setup([["x.rb", "X = 1"]]) do
      args = []; loader.on_unload { |*a| args << a }

      assert X
      loader.reload

      assert_equal 1, args.length
      assert_equal "X", args[0][0]
      assert_equal 1, args[0][1]
      assert_abspath "x.rb", args[0][2]
    end
  end

  test "multiple on_unload for :ANY are called in order of definition" do
    with_setup([["x.rb", "X = 1"]]) do
      x = []
      loader.on_unload { x << 1 }
      loader.on_unload { x << 2 }

      assert X
      loader.reload

      assert_equal [1, 2], x
    end
  end

  test "if there are specific and :ANY on_unloads, the specific one runs first" do
    with_setup([["x.rb", "X = 1"]]) do
      x = []
      loader.on_unload { x << 2 }
      loader.on_unload("X") { x << 1 }

      assert X
      loader.reload

      assert_equal [1, 2], x
    end
  end
end
