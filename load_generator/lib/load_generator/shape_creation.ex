defmodule LoadGenerator.ShapeCreation do
  use Supervisor

  require Logger

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    parallel = Keyword.get(args, :parallel, 5)
    table = Keyword.fetch!(args, :table)
    {column, partitions} = LoadGenerator.PartitionSupervisor.all_partitions()

    Logger.info("creating #{length(partitions)} shapes")

    size = div(length(partitions), parallel) + 1

    groups = Enum.chunk_every(partitions, size)

    count = length(groups)

    {:ok, client} = LoadGenerator.ClientManager.client()

    children =
      groups
      |> Enum.with_index()
      |> Enum.map(fn {ids, i} ->
        Supervisor.child_spec({Task, fn -> run(i, count, client, table, column, ids) end},
          id: {:creator, i}
        )
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end

  def run(i, count, client, table, column, ids) do
    n = length(ids)
    IO.inspect(create_thread: {i, count, n})

    for {id, _i} <- Enum.with_index(ids, 1) do
      {:ok, shape} = LoadGenerator.ClientManager.shape(table, column, id)
      shape_params = Electric.Client.ShapeDefinition.params(shape)

      request =
        Electric.Client.request(client,
          offset: "-1",
          params: shape_params
        )

      %{status: 200} = Electric.Client.Fetch.request(client, request)
      LoadGenerator.Stats.register_stat(:shape_init)
    end

    IO.inspect(done: i, total: count, n: n)
  end
end
