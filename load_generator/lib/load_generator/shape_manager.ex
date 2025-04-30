defmodule LoadGenerator.ShapeManager do
  use GenServer

  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def register_consumer(handle, pid \\ self()) do
    GenServer.call(__MODULE__, {:register_consumer, handle, pid})
  end

  def unregister_consumer(pid \\ self()) do
    GenServer.call(__MODULE__, {:unregister_consumer, pid})
  end

  def init(args) do
    frequency = Keyword.fetch!(args, :frequency)
    electric_url = Keyword.fetch!(args, :electric_url)

    state = %{
      electric_url: electric_url,
      frequency: frequency,
      handles: %{},
      pids: %{}
    }

    {:ok, schedule_deletion(state)}
  end

  def handle_call({:register_consumer, handle, pid}, _from, state) do
    Logger.debug(handle: handle, size: map_size(state.handles), pids: map_size(state.pids))

    if !Map.has_key?(state.handles, handle) do
      LoadGenerator.Stats.register_stat(:shape_create)
    end

    Process.monitor(pid)

    handles = Map.update(state.handles, handle, [pid], &[pid | &1])
    pids = Map.put(state.pids, pid, handle)

    {:reply, :ok, %{state | handles: handles, pids: pids}}
  end

  def handle_call({:unregister_consumer, pid}, _from, state) do
    state = remove_consumer(pid, state)

    {:reply, :ok, state}
  end

  def handle_info(:delete_shape, state) do
    state =
      case Map.keys(state.handles) do
        [] ->
          state

        handles ->
          handle = Enum.random(handles)

          handles = Map.delete(state.handles, handle)

          delete_shape(handle, state)

          %{state | handles: handles}
      end

    {:noreply, schedule_deletion(state)}
  end

  def handle_info({:DOWN, _ref, :process, pid, _}, state) do
    state = remove_consumer(pid, state)

    {:noreply, state}
  end

  defp schedule_deletion(state) do
    Process.send_after(self(), :delete_shape, :rand.uniform(state.frequency * 2))
    state
  end

  defp remove_consumer(pid, state) do
    {handle, pids} = Map.pop(state.pids, pid)

    handles =
      case Map.get_and_update(state.handles, handle, fn
             pids when is_list(pids) ->
               pids = List.delete(pids, pid)
               {pids, pids}

             nil ->
               {[], []}
           end) do
        {[], handles} ->
          delete_shape(handle, state)
          Map.delete(handles, handle)

        {_pids, handles} ->
          handles
      end

    %{state | pids: pids, handles: handles}
  end

  defp delete_shape(nil, _state) do
    :ok
  end

  defp delete_shape(handle, state) do
    {:ok, %{status: status}} =
      Req.delete("#{state.electric_url}/v1/shape", params: %{handle: handle})

    if status in 200..299, do: LoadGenerator.Stats.register_stat(:shape_delete)

    :ok
  end
end
