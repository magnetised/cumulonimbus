defmodule LoadGenerator.Stream do
  defstruct [:columns, :format, :types, :partition]

  def new(columns, format \\ :string) do
    types = Map.new(columns, &{&1.name, &1.type})
    %LoadGenerator.Stream{columns: columns, format: format, types: types}
  end

  def partition(%__MODULE__{} = stream, {%{name: partition_column} = column, value}) do
    Map.update!(stream, :columns, fn columns ->
      Enum.map(columns, fn
        %{name: ^partition_column} ->
          %LoadGenerator.Column.Static{name: partition_column, column: column, value: value}

        column ->
          column
      end)
    end)
  end

  def row(%__MODULE__{} = stream) do
    %{columns: columns, format: format, types: types} = stream

    columns
    |> values()
    |> format(types, format)
  end

  defp values(columns) do
    Map.new(columns, fn column ->
      {column.name, LoadGenerator.Column.generate(column)}
    end)
  end

  def format(values, _types, :string) do
    values
  end

  def format(values, types, :binary) do
    Map.new(values, &binary_format(&1, types))
  end

  defp binary_format({column, value}, types) do
    {column, binary_column(value, Map.fetch!(types, column))}
  end

  defp binary_column(uuid, "uuid") do
    UUID.string_to_binary!(uuid)
  end

  defp binary_column(value, _type) do
    value
  end

  defimpl Enumerable do
    def count(_generator), do: {:error, __MODULE__}
    def member?(_generator, _element), do: {:error, __MODULE__}
    def slice(_generator), do: {:error, __MODULE__}

    def reduce(_generator, {:halt, acc}, _fun) do
      {:halted, acc}
    end

    def reduce(generator, {:suspend, acc}, fun) do
      {:suspended, acc, &reduce(generator, &1, fun)}
    end

    def reduce(generator, {:cont, acc}, fun) do
      row = LoadGenerator.Stream.row(generator)
      reduce(generator, fun.(row, acc), fun)
    end
  end
end
