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

    children = [
      {Registry, name: @process_registry_name, keys: :unique},
      LoadGenerator.Stats,
      {LoadGenerator.Scenario,
       scenario: LoadGenerator.Scenario.Turbo,
       db: db,
       electric_url: electric_url,
       table: table,
       source_id: source_id,
       source_secret: source_secret}
    ]

    opts = [
      strategy: :one_for_one,
      # max_restarts: 0,
      # auto_shutdown: :any_significant,
      name: LoadGenerator.Supervisor
    ]

    Supervisor.start_link(children, opts)
  end
end
