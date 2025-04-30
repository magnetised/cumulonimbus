defmodule LoadGenerator.PartitionsTest do
  use ExUnit.Case, async: true

  alias LoadGenerator.Partitions
  alias LoadGenerator.Partition
  alias LoadGenerator.Column

  describe "generate/3" do
    test "generates partitions with sequential integer ids" do
      columns = [
        Column.new!(name: "account_id", type: "integer"),
        Column.new!(name: "name", type: "text", generation_size: 32..128),
        Column.new!(name: "value", type: "integer")
      ]

      [%Partition{} | _] = partitions = Partitions.generate(["account_id"], columns, 10)

      assert Enum.map(partitions, & &1.id["account_id"]) == Enum.to_list(1..10)
    end

    test "generates partitions with random uuid ids" do
      columns = [
        Column.new!(name: "account_id", type: "uuid"),
        Column.new!(name: "name", type: "text", generation_size: 32..128),
        Column.new!(name: "value", type: "integer")
      ]

      [%Partition{} | _] = partitions = Partitions.generate(["account_id"], columns, 10)

      assert Enum.map(partitions, & &1.id["account_id"]) |> Enum.uniq() |> length() == 10
    end

    test "generates partitions with random text ids" do
      columns = [
        Column.new!(name: "account_id", type: "text", generation_size: 32),
        Column.new!(name: "name", type: "text", generation_size: 32..128),
        Column.new!(name: "value", type: "integer")
      ]

      [%Partition{} | _] = partitions = Partitions.generate(["account_id"], columns, 10)

      assert Enum.map(partitions, & &1.id["account_id"]) |> Enum.uniq() |> length() == 10
    end
  end

  describe "start_link/1" do
    test "starts a genserver for every partition" do
      columns = [
        Column.new!(name: "account_id", type: "integer"),
        Column.new!(name: "name", type: "text", generation_size: 32..128),
        Column.new!(name: "value", type: "integer")
      ]

      parent = self()

      {:ok, _supervisor} =
        start_supervised(
          {
            Partitions,
            name: "account",
            table: "items",
            id_column_names: ["account_id"],
            columns: columns,
            partitions: 10,
            interval: 1,
            insert: fn table, row ->
              send(parent, {:row, table, row})
            end,
            rows: [count: 2]
          },
          shutdown: :brutal_kill
        )

      ids =
        for n <- 1..20 do
          assert_receive {:row, "items", %{"account_id" => id}}
          id
        end

      assert Enum.uniq(ids) |> Enum.sort() == Enum.to_list(1..10)
    end

    test "allows interval to be a range" do
      columns = [
        Column.new!(name: "account_id", type: "integer"),
        Column.new!(name: "name", type: "text", generation_size: 32..128),
        Column.new!(name: "value", type: "integer")
      ]

      parent = self()

      {:ok, _supervisor} =
        start_supervised(
          {Partitions,
           name: "account2",
           table: "items",
           id_column_names: ["account_id"],
           columns: columns,
           partitions: 10,
           interval: 1..2,
           insert: fn table, row ->
             send(parent, {:row, table, row})
           end,
           rows: [count: 1]},
          shutdown: :brutal_kill
        )

      ids =
        for n <- 1..10 do
          assert_receive {:row, "items", %{"account_id" => id}}
          id
        end

      assert Enum.sort(ids) == Enum.to_list(1..10)
    end

    test "allows interval to be a function" do
      columns = [
        Column.new!(name: "account_id", type: "integer"),
        Column.new!(name: "name", type: "text", generation_size: 32..128),
        Column.new!(name: "value", type: "integer")
      ]

      parent = self()

      {:ok, supervisor} =
        start_supervised(
          {Partitions,
           name: "account3",
           table: "items",
           id_column_names: ["account_id"],
           columns: columns,
           partitions: 10,
           interval: fn -> Enum.random(1..2) end,
           insert: fn table, row ->
             send(parent, {:row, table, row})
           end,
           rows: [count: 1]},
          shutdown: :brutal_kill
        )

      ids =
        for n <- 1..10 do
          assert_receive {:row, "items", %{"account_id" => id}}
          id
        end

      assert Enum.sort(ids) == Enum.to_list(1..10)
    end
  end
end
