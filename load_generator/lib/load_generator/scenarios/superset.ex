defmodule LoadGenerator.Scenario.Superset do
  use Supervisor

  alias LoadGenerator.Column

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    # in this scenario, don't expect to see a lot of messages from the clients --
    # there are so many partitions that each doesn't get much activity
    db = Keyword.fetch!(args, :db)
    electric_urls = Keyword.fetch!(args, :electric_urls)
    table = Keyword.fetch!(args, :table)
    source_id = Keyword.fetch!(args, :source_id)
    source_secret = Keyword.fetch!(args, :source_secret)
    clients = 50_000

    children = [
      {DynamicSupervisor,
       name: LoadGenerator.ClientSupervisor, max_restarts: clients, max_seconds: 60 * 60},
      {LoadGenerator.DB, db: db, pool_size: 100},
      {LoadGenerator.ShapeManager,
       frequency: 1000, electric_url: hd(electric_urls), delete: true, delete_unused: false},
      {
        LoadGenerator.PartitionSupervisor,
        tps: [5, 5],
        max_rows: 20,
        partitions: 100_000,
        partition_column: "partition_id",
        table: table,
        get_existing: true,
        columns: [
          Column.new!(name: "partition_id", type: "uuid"),
          Column.new!(name: "value", type: "text", generation_size: 256)
        ]
      },
      {LoadGenerator.ClientManager,
       max_clients: clients,
       urls: electric_urls,
       params: %{source_id: source_id, secret: source_secret},
       table: table,
       mean_client_lifetime: 120_000},
      # disabled for now as migrating the table while a snapshot is being created results
      # in client errors and we're trying to detect client errors as proof of a bug
      #
      # {LoadGenerator.TableMutator,
      #  table: table, column: "mutating", types: ["text", "integer"], frequency: 10_000},
      {LoadGenerator.ShapeCreation, [table: table, parallel: 1000]}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
