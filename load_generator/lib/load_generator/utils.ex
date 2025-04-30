defmodule LoadGenerator.Utils do
  @doc """
  ## Examples

      iex> LoadGenerator.Utils.parse_range("10")
      {:ok, 10}

      iex> LoadGenerator.Utils.parse_range("10..1000")
      {:ok, 10..1000}

      iex> LoadGenerator.Utils.parse_range("10..")
      {:error, "Invalid range: \\"10..\\""}

      iex> LoadGenerator.Utils.parse_range("hmm")
      {:error, "Invalid range: \\"hmm\\""}

  """
  def parse_range(spec) when is_binary(spec) do
    case Integer.parse(spec) do
      {min, ".." <> rest} ->
        case Integer.parse(rest) do
          {max, _} ->
            {:ok, Range.new(min, max)}

          :error ->
            {:error, "Invalid range: #{inspect(spec)}"}
        end

      {value, ""} ->
        {:ok, value}

      :error ->
        {:error, "Invalid range: #{inspect(spec)}"}
    end
  end
end
