defmodule LoadGenerator.PartitionSupervisor do
  use Supervisor

  defmodule State do
    use Agent

    def start_link({partition_column, partitions}) do
      Agent.start_link(fn -> {partition_column, partitions} end, name: __MODULE__)
    end

    def partition do
      Agent.get(__MODULE__, fn {partition_column, partitions} ->
        {partition_column, Enum.random(partitions)}
      end)
    end
  end

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def random_partition do
    State.partition()
  end

  def init(args) do
    table = Keyword.fetch!(args, :table)
    columns = Keyword.fetch!(args, :columns)
    partition_count = Keyword.fetch!(args, :partitions)
    partition_column_name = Keyword.fetch!(args, :partition_column)
    tps = Keyword.fetch!(args, :tps)

    partition_column =
      Enum.find(columns, &(&1.name == partition_column_name)) ||
        raise "invalid partition_column_name #{inspect(partition_column_name)}"

    partitions =
      Enum.map(1..partition_count, fn _ ->
        {partition_column, LoadGenerator.Column.generate(partition_column)}
      end)

    streams =
      Enum.map(partitions, fn {_, value} = partition ->
        {value, LoadGenerator.partition_stream(columns, partition, :binary)}
      end)

    generator_tps = tps / partition_count

    generators =
      Enum.map(streams, fn {id, stream} ->
        {LoadGenerator.DbLoad, id: id, table: table, stream: stream, tps: generator_tps}
      end)

    children =
      [
        {State, {partition_column_name, Enum.map(partitions, &elem(&1, 1))}}
      ] ++ generators

    Supervisor.init(children, strategy: :one_for_all)
  end
end
