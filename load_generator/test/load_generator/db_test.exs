defmodule LoadGenerator.DBTest do
  use ExUnit.Case, async: true
  alias LoadGenerator.DB

  test "start_link connects to db using uri" do
    {:ok, _pool} =
      start_supervised(
        {DB, "postgresql://postgres:password@localhost:5432/electric?sslmode=disable"}
      )

    assert %Postgrex.Result{num_rows: 5} =
             DB.query!("SELECT * FROM information_schema.tables LIMIT 5", [])
  end

  describe "insert_query/2" do
    test "generates a valid insert statement" do
      assert {~s[INSERT INTO "items" ("age", "id", "name") VALUES ($1, $2, $3)], [23, 5, "Mike"]} ==
               DB.insert_query("items", %{"id" => 5, "name" => "Mike", "age" => 23})
    end
  end
end
