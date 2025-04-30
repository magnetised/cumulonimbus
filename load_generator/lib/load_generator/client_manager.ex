defmodule LoadGenerator.ClientManager do
  use GenServer, significant: true, restart: :transient

  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    {:ok, clients} = Keyword.fetch(args, :max_clients)
    {:ok, electric_url} = Keyword.fetch(args, :url)
    {:ok, table} = Keyword.fetch(args, :table)
    mean_client_lifetime = Keyword.get(args, :mean_client_lifetime, 30_000)
    _where = Keyword.get(args, :where, nil)

    state = %{
      max_clients: clients,
      mean_client_lifetime: mean_client_lifetime,
      electric_url: electric_url,
      table: table,
      client_id: 0
    }

    {:ok, state, {:continue, :start_clients}}
  end

  def handle_continue(:start_clients, state) do
    interval = 50

    Logger.info("Starting #{state.max_clients} clients")

    state =
      Enum.reduce(1..state.max_clients, state, fn _, state ->
        state = start_client(state)

        Process.sleep(interval)
        state
      end)

    {:noreply, state}
  end

  def handle_info({:terminate_client, id, pid, ref}, state) do
    Process.exit(pid, {:shutdown, :normal})

    receive do
      {:DOWN, ^ref, :process, ^pid, _} ->
        Logger.debug("Client #{id} terminated")
        {:noreply, start_client(state)}
    after
      5_000 ->
        Logger.error("Failed to stop client #{id} within 5000 ms")
        {:error, state}
    end
  end

  def handle_info({:DOWN, _ref, :process, _pid, _}, state) do
    Logger.warning("Client crashed, stopping")
    {:stop, :error, state}
  end

  defp start_client(%{client_id: client_id} = state) do
    {:ok, _pid, _ref} = start_client(client_id, state)
    %{state | client_id: client_id + 1}
  end

  defp start_client(id, state) do
    {:ok, client} =
      Electric.Client.new(
        base_url: state.electric_url,
        pool: {LoadGenerator.Mint, []},
        fetch: {LoadGenerator.Mint, []}
      )

    {column, partition} = LoadGenerator.PartitionSupervisor.random_partition()

    where = "#{column} = '#{partition}'"

    {:ok, shape} = Electric.Client.shape(state.table, where: where)

    stream = Electric.Client.stream(client, shape)

    lifetime = :rand.uniform(state.mean_client_lifetime)
    # round(:rand.uniform(round(state.mean_client_lifetime / 2)) + state.mean_client_lifetime / 2)

    {:ok, pid} =
      DynamicSupervisor.start_child(
        LoadGenerator.ClientSupervisor,
        {LoadGenerator.Client, stream: stream, id: id}
      )

    ref = Process.monitor(pid)

    Logger.debug("started client #{id} with lifetime #{lifetime}")
    Process.send_after(self(), {:terminate_client, id, pid, ref}, lifetime)

    {:ok, pid, ref}
  end
end
