defmodule LoadGenerator.Column do
  @valid_types ~w(uuid text integer)

  defstruct [:name, :type, :generation_size]

  defguardp is_range(range) when is_struct(range, Range)

  defmodule Static do
    defstruct [:name, :column, :value]
  end

  def new(attrs) do
    struct(__MODULE__, attrs)
    |> validate!()
  end

  def new!(attrs) do
    case new(attrs) do
      {:ok, column} -> column
      {:error, msg} -> raise ArgumentError, message: msg
    end
  end

  defp validate!(column) do
    case column do
      %{name: name} when name in [nil, ""] ->
        {:error, "Missing column name"}

      %{type: type} when type not in @valid_types ->
        {:error, "Invalid type: #{type}. Accepted values: #{Enum.join(@valid_types, ",")}"}

      valid ->
        {:ok, valid}
    end
  end

  def parse_spec(spec) do
    case :binary.split(spec, ":", [:global, :trim_all]) do
      [name] ->
        new(name: name, type: "text")

      [name, type] ->
        new(name: name, type: type)

      [name, type, generation_size] ->
        with {:ok, size} <- LoadGenerator.Utils.parse_range(generation_size) do
          new(name: name, type: type, generation_size: size)
        end
    end
  end

  def parse_spec!(spec) do
    case parse_spec(spec) do
      {:ok, column} -> column
      {:error, msg} -> raise ArgumentError, message: msg
    end
  end

  def generate(%Static{} = column) do
    column.value
  end

  def generate(%__MODULE__{} = column) do
    generate(column.type, column.generation_size)
  end

  defp generate("text", nil) do
    generate("text", 10..128)
  end

  defp generate("text", size) when is_integer(size) do
    generate_text(size)
  end

  defp generate("text", range) when is_range(range) do
    range
    |> Enum.random()
    |> generate_text()
  end

  defp generate("uuid", _) do
    UUID.uuid4()
  end

  defp generate("integer", nil) do
    generate("integer", 0..1024)
  end

  defp generate("integer", max) when is_integer(max) do
    Enum.random(0..max)
  end

  defp generate("integer", range) when is_range(range) do
    Enum.random(range)
  end

  defp generate_text(chars) do
    source_bytes = Float.ceil(chars * (5.0 / 8.0)) |> round()

    source_bytes
    |> :crypto.strong_rand_bytes()
    |> Base.encode32(padding: false, case: :lower)
    |> binary_part(0, chars)
  end
end
