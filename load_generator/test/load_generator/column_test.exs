defmodule LoadGenerator.ColumnTest do
  use ExUnit.Case, async: true

  alias LoadGenerator.Column

  describe "parse_spec/1" do
    test "accepts name and defaults to text" do
      assert {:ok, %Column{name: "name", type: "text", generation_size: nil}} =
               Column.parse_spec("name")
    end

    test "accepts name:type" do
      assert {:ok, %Column{name: "id", type: "uuid", generation_size: nil}} =
               Column.parse_spec("id:uuid")
    end

    test "understands size range" do
      assert {:ok, %Column{name: "name", type: "text", generation_size: 10..1024}} =
               Column.parse_spec("name:text:10..1024")
    end

    test "understands fixed size" do
      assert {:ok, %Column{name: "name", type: "text", generation_size: 10}} =
               Column.parse_spec("name:text:10")
    end

    test "catches invalid types" do
      assert {:error, _} = Column.parse_spec("name:flimg:10")
    end

    test "catches invalid sizes" do
      assert {:error, _} = Column.parse_spec("name:text:cow")
      assert {:error, _} = Column.parse_spec("name:text:1..boom")
    end
  end

  describe "generate/1" do
    defp generate(attrs) do
      attrs
      |> Column.new!()
      |> Column.generate()
    end

    defp generate_size(attrs) do
      attrs
      |> generate()
      |> byte_size()
    end

    test "text: fixed-size" do
      assert generate_size(name: "name", type: "text", generation_size: 10) == 10
    end

    test "text: range" do
      assert generate_size(name: "name", type: "text", generation_size: 10..100) in 10..100
    end

    test "text: default" do
      assert generate_size(name: "name", type: "text") in 10..128
    end

    test "uuid" do
      assert generate_size(name: "name", type: "uuid") ==
               byte_size("00000000-0000-4000-0000-000000000000")
    end

    test "integer: fixed-size" do
      assert generate(name: "name", type: "integer", generation_size: 10) <= 10
    end

    test "integer: range" do
      assert generate(name: "name", type: "integer", generation_size: 99..1000) in 99..1000
    end

    test "integer: default" do
      assert generate(name: "name", type: "integer") in 0..1024
    end
  end
end
