defmodule LoadGenerator.PartitionTest do
  use ExUnit.Case, async: true

  alias LoadGenerator.Partition
  alias LoadGenerator.Column

  describe "Enumerable" do
    test "generates random rows based on id" do
      columns = [
        Column.new!(name: "name", type: "text", generation_size: 32..128),
        Column.new!(name: "value", type: "integer")
      ]

      id_columns = [
        Column.new!(name: "id1", type: "integer"),
        Column.new!(name: "id2", type: "integer")
      ]

      id = %{"id1" => 1, "id2" => 2}
      partition = Partition.new(id, id_columns, columns)

      values =
        for row <- partition |> Enum.take(10) do
          %{"id1" => 1, "id2" => 2, "name" => name, "value" => value} = row

          {name, value}
        end

      assert length(Enum.uniq(values)) == length(values)
    end
  end
end
