defmodule LoadGenerator.ClientManager do
  use GenServer, significant: true, restart: :transient

  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def consumer_ready(id, handle, pid \\ self()) do
    GenServer.cast(__MODULE__, {:consumer_ready, id, handle, pid})
  end

  def init(args) do
    Process.flag(:trap_exit, true)
    {:ok, clients} = Keyword.fetch(args, :max_clients)
    {:ok, electric_url} = Keyword.fetch(args, :url)
    {:ok, table} = Keyword.fetch(args, :table)
    params = Keyword.get(args, :params, %{})
    mean_client_lifetime = Keyword.get(args, :mean_client_lifetime, 30_000)
    _where = Keyword.get(args, :where, nil)

    state = %{
      max_clients: clients,
      mean_client_lifetime: mean_client_lifetime,
      electric_url: electric_url,
      params: params,
      table: table,
      client_id: 0
    }

    send(self(), {:start_client, clients})

    {:ok, state}
  end

  def handle_continue(:start_clients, state) do
    interval = 100

    Logger.info("Starting #{state.max_clients} clients")

    state =
      Enum.reduce(1..state.max_clients, state, fn _, state ->
        state = start_client(state)

        Process.sleep(interval)
        state
      end)

    {:noreply, state}
  end

  def handle_cast({:consumer_ready, id, _handle, pid}, state) do
    # only schedule the client for termination once it's finished downloading a snapshot chunk
    lifetime = :rand.uniform(state.mean_client_lifetime)
    # round(:rand.uniform(round(state.mean_client_lifetime / 2)) + state.mean_client_lifetime / 2)

    Logger.debug("client #{id} with lifetime #{lifetime}")
    # Process.send_after(self(), {:terminate_client, id, pid}, lifetime)

    {:noreply, state}
  end

  def handle_info({:start_client, 0}, state) do
    Logger.info("Started #{state.max_clients} clients")
    {:noreply, state}
  end

  def handle_info({:start_client, n}, state) do
    state = start_client(state)

    Process.send_after(self(), {:start_client, n - 1}, 50)

    {:noreply, state}
  end

  def handle_info({:terminate_client, id, pid}, state) do
    Process.exit(pid, {:shutdown, :normal})

    receive do
      {:DOWN, _ref, :process, ^pid, _} ->
        Logger.debug("Client #{id} terminated")
        LoadGenerator.Stats.register_stat(:active_client, -1)
        {:noreply, start_client(state)}
    after
      30_000 ->
        Logger.error("Failed to stop client #{id} within 5000 ms")
        {:stop, :error, state}
    end
  end

  def handle_info({:DOWN, _ref, :process, _pid, _}, state) do
    Logger.warning("Client crashed, restarting")
    LoadGenerator.Stats.register_stat(:active_client, -1)
    # {:stop, :error, state}
    {:noreply, start_client(state)}
  end

  def handle_info({:EXIT, _pid, :shutdown}, state) do
    Logger.warning("Client crashed")
    LoadGenerator.Stats.register_stat(:active_client, -1)

    {:noreply, state}
  end

  defp start_client(%{client_id: client_id} = state) do
    {:ok, _pid} = start_client(client_id, state)
    %{state | client_id: client_id + 1}
  end

  defp start_client(id, state) do
    {:ok, client} =
      Electric.Client.new(
        base_url: state.electric_url,
        pool: {LoadGenerator.Mint, []},
        # fetch: {Electric.Client.Fetch.HTTP, [request: [finch: LoadGenerator.Finch, retry: false]]}
        fetch: {LoadGenerator.Mint, []},
        params: state.params
      )

    {column, partition} = LoadGenerator.PartitionSupervisor.random_partition()

    where = "#{column} = '#{partition}'"

    {:ok, shape} = Electric.Client.shape(state.table, where: where)

    stream = Electric.Client.stream(client, shape)

    {:ok, pid} =
      DynamicSupervisor.start_child(
        LoadGenerator.ClientSupervisor,
        {LoadGenerator.Client, stream: stream, client: client, id: id}
      )

    _ref = Process.monitor(pid)

    {:ok, pid}
  end
end
