defmodule LoadGenerator.ShapeManager do
  use GenServer

  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def register_consumer(handle, pid \\ self()) do
    GenServer.call(__MODULE__, {:register_consumer, handle, pid}, :infinity)
  end

  def unregister_consumer(pid \\ self()) do
    GenServer.call(__MODULE__, {:unregister_consumer, pid}, :infinity)
  end

  def init(args) do
    frequency = Keyword.fetch!(args, :frequency)
    electric_url = Keyword.fetch!(args, :electric_url)
    delete = Keyword.get(args, :delete, true)
    delete_unused = Keyword.get(args, :delete_unused, true)

    state = %{
      electric_url: electric_url,
      frequency: frequency,
      handles: %{},
      shapes: MapSet.new(),
      pids: %{},
      delete: delete,
      delete_unused: delete_unused
    }

    {:ok, schedule_deletion(state)}
  end

  def handle_call({:register_consumer, handle, pid}, _from, state) do
    Logger.debug(handle: handle, size: map_size(state.handles), pids: map_size(state.pids))

    if !MapSet.member?(state.shapes, handle) do
      LoadGenerator.Stats.register_stat(:shape_create)
    end

    Process.monitor(pid)

    handles = Map.update(state.handles, handle, [pid], &[pid | &1])
    pids = Map.put(state.pids, pid, handle)

    {:reply, :ok,
     %{state | handles: handles, pids: pids, shapes: MapSet.put(state.shapes, handle)}}
  end

  def handle_call({:unregister_consumer, pid}, _from, state) do
    state = remove_consumer(pid, state)

    {:reply, :ok, state}
  end

  def handle_info(:delete_shape, state) do
    dbg(delete: Map.size(state.handles))

    state =
      case Map.keys(state.handles) do
        [] ->
          state

        handles ->
          handle = Enum.random(handles)

          handles = Map.delete(state.handles, handle)

          delete_shape(handle, %{state | handles: handles})
      end

    {:noreply, schedule_deletion(state)}
  end

  def handle_info({:DOWN, _ref, :process, pid, _}, state) do
    state = remove_consumer(pid, state)

    {:noreply, state}
  end

  defp schedule_deletion(state) do
    if state.delete,
      do: Process.send_after(self(), :delete_shape, :rand.uniform(state.frequency * 2))

    state
  end

  defp remove_consumer(pid, state) do
    {handle, pids} = Map.pop(state.pids, pid)

    state =
      case Map.get_and_update(state.handles, handle, fn
             pids when is_list(pids) ->
               pids = List.delete(pids, pid)
               {pids, pids}

             nil ->
               {[], []}
           end) do
        {[], handles} ->
          if state.delete_unused,
            do: delete_shape(handle, %{state | handles: Map.delete(handles, handle)}),
            else: state

        {_pids, _handles} ->
          state
      end

    %{state | pids: pids}
  end

  defp delete_shape(nil, state) do
    state
  end

  defp delete_shape(handle, state, n \\ 1) when n < 10 do
    case Req.delete("#{state.electric_url}/v1/shape", params: %{handle: handle}) do
      {:ok, %{status: status}} ->
        if status in 200..299 do
          LoadGenerator.Stats.register_stat(:shape_delete)
          Logger.debug("Deleted shape #{handle}")
        end

        %{state | shapes: MapSet.delete(state.shapes, handle)}

      {:error, %Req.TransportError{}} ->
        Process.sleep(100)
        delete_shape(handle, state, n + 1)
    end
  end
end
