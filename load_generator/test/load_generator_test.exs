defmodule LoadGeneratorTest do
  use ExUnit.Case

  alias LoadGenerator.Column

  describe "value_stream/1" do
    test "generates a map of generated values" do
      columns = [
        Column.new!(name: "id", type: "uuid"),
        Column.new!(name: "name", type: "text", generation_size: 5..16),
        Column.new!(name: "age", type: "integer", generation_size: 12..71)
      ]

      ids =
        for row <- LoadGenerator.row_stream(columns) |> Stream.take(10) do
          assert %{"id" => id, "name" => name, "age" => age} = row
          assert byte_size(name) in 5..16
          assert age in 12..71
          id
        end

      assert length(Enum.uniq(ids)) == length(ids)
    end
  end
end
