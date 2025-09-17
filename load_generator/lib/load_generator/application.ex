defmodule LoadGenerator.Application do
  @moduledoc false

  use Application

  alias LoadGenerator.Column

  @process_registry_name __MODULE__.Registry

  def name(id) do
    {:via, Registry, {@process_registry_name, id}}
  end

  @impl true
  def start(_type, _args) do
    db = System.get_env("DATABASE_URL") || raise "Missing DATABASE_URL"
    electric_url = System.get_env("ELECTRIC_URL") || raise "Missing ELECTRIC_URL"
    table = System.get_env("TABLE", "items") |> dbg
    source_id = System.get_env("SOURCE_ID") || raise "Missing SOURCE_ID"
    source_secret = System.get_env("SECRET") || raise "Missing SECRET"
    clients = 500

    children = [
      {Registry, name: @process_registry_name, keys: :unique},
      LoadGenerator.Stats,
      {DynamicSupervisor, name: LoadGenerator.ClientSupervisor, max_restarts: clients},
      {LoadGenerator.DB, db: db},
      {LoadGenerator.ShapeManager, frequency: 2_000, electric_url: electric_url},
      {
        LoadGenerator.PartitionSupervisor,
        tps: [1, 1],
        max_rows: 2_000,
        partitions: 100,
        partition_column: "partition_id",
        table: table,
        columns: [
          Column.new!(name: "partition_id", type: "uuid"),
          Column.new!(name: "value", type: "text", generation_size: 128)
        ]
      },
      {LoadGenerator.ClientManager,
       max_clients: clients,
       url: electric_url,
       params: %{source_id: source_id, secret: source_secret},
       table: table,
       mean_client_lifetime: 2_000}
      # disabled for now as migrating the table while a snapshot is being created results
      # in client errors and we're trying to detect client errors as proof of a bug
      #
      # {LoadGenerator.TableMutator,
      #  table: table, column: "mutating", types: ["text", "integer"], frequency: 10_000},
    ]

    opts = [
      strategy: :one_for_one,
      # max_restarts: 0,
      auto_shutdown: :any_significant,
      name: LoadGenerator.Supervisor
    ]

    Supervisor.start_link(children, opts)
  end
end
