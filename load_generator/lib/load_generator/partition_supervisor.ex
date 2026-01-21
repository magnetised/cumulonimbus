defmodule LoadGenerator.PartitionSupervisor do
  use Supervisor

  defmodule State do
    use Agent

    def start_link({partition_column, partitions, n, i}) do
      Agent.start_link(fn -> {partition_column, partitions, n, i} end, name: __MODULE__)
    end

    def all_partitions do
      Agent.get(__MODULE__, fn {partition_column, partitions, _n, _i} ->
        {partition_column, partitions}
      end)
    end

    def partition do
      Agent.get_and_update(__MODULE__, fn {partition_column, partitions, n, i} ->
        {
          {partition_column, Enum.random(partitions)},
          {partition_column, partitions, n, rem(i + 1, n)}
        }
      end)
    end
  end

  require Logger

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def random_partition do
    State.partition()
  end

  def all_partitions do
    State.all_partitions()
  end

  def init(args) do
    table = Keyword.fetch!(args, :table)
    columns = Keyword.fetch!(args, :columns)
    partition_count = Keyword.fetch!(args, :partitions)
    partition_column_name = Keyword.fetch!(args, :partition_column)
    [ftps, stps] = Keyword.fetch!(args, :tps)
    max_rows = Keyword.fetch!(args, :max_rows)
    # get_existing? = Keyword.get(args, :get_existing, false)

    partition_column =
      Enum.find(columns, &(&1.name == partition_column_name)) ||
        raise "invalid partition_column_name #{inspect(partition_column_name)}"

    {existing_partitions, generate_count} =
      calculate_generate_count(table, partition_column, partition_count)

    Logger.info("Creating #{generate_count} partitions to reach #{partition_count}")

    new_partitions =
      Enum.map(1..generate_count, fn _ ->
        {partition_column, LoadGenerator.Column.generate(partition_column)}
      end)

    Logger.info("creating #{generate_count} new partitions")

    Enum.each(new_partitions, fn {_, _} = partition ->
      LoadGenerator.partition_stream(columns, partition, :binary)
      |> Stream.take(1)
      |> Enum.each(fn row ->
        LoadGenerator.DB.insert!(table, row)
      end)
    end)

    partitions = Enum.concat(existing_partitions, new_partitions)

    streams =
      Enum.map(partitions, fn {_, value} = partition ->
        {value, LoadGenerator.partition_stream(columns, partition, :binary)}
      end)

    # generator_ftps = ftps / partition_count
    # generator_stps = stps / partition_count

    children =
      [
        {State,
         {partition_column_name, Enum.map(partitions, &elem(&1, 1)), length(partitions), 0}},
        {LoadGenerator.Turbo.DbLoad,
         id: 1,
         table: table,
         streams: Stream.repeatedly(fn -> Enum.random(streams) end),
         tps: [ftps, stps],
         max_rows: max_rows,
         rows_per_partition: 2..10},
        {LoadGenerator.Turbo.DbLoad,
         id: 2,
         table: table,
         streams: Stream.repeatedly(fn -> Enum.random(streams) end),
         tps: [ftps, stps],
         max_rows: max_rows,
         rows_per_partition: 2..10},
        {LoadGenerator.Turbo.DbLoad,
         id: 3,
         table: table,
         streams: Stream.repeatedly(fn -> Enum.random(streams) end),
         tps: [ftps, stps],
         max_rows: max_rows,
         rows_per_partition: 2..4}
      ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  defp calculate_generate_count(table, column, count) do
    %{rows: partitions, num_rows: rows} =
      LoadGenerator.DB.query!(
        "SELECT #{column.name} FROM (SELECT DISTINCT #{column.name} FROM #{table}) LIMIT #{count}",
        []
      )

    {Enum.zip(
       Stream.repeatedly(fn -> column end) |> Enum.take(rows),
       Stream.map(partitions, fn [value] -> LoadGenerator.Column.load!(column, value) end)
     ), max(0, count - rows)}
  end
end
