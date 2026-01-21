defmodule LoadGenerator.Client do
  use Task, restart: :temporary

  require Logger

  def child_spec(arg) do
    id = Keyword.fetch!(arg, :id)

    %{
      id: {__MODULE__, id},
      start: {__MODULE__, :start_link, [arg]},
      restart: :transient
    }
  end

  def start_link(args) do
    Task.start_link(__MODULE__, :run, [args])
  end

  def run(args) do
    client_id = Keyword.fetch!(args, :id)
    stream = Keyword.fetch!(args, :stream)
    LoadGenerator.Stats.register_stat(:client)
    LoadGenerator.Stats.register_stat(:active_client)

    try do
      Enum.reduce(stream, {0, nil, false, false}, fn msg, {c, handle, monitored?, registered?} ->
        # dbg(msg)

        case msg do
          %Electric.Client.Message.ChangeMessage{
            value: %{"id" => row_id},
            headers: %{operation: _operation, handle: handle},
            request_timestamp: _request_timestamp
          } ->
            if !monitored?, do: LoadGenerator.ClientManager.consumer_ready(client_id, handle)

            if !registered?, do: LoadGenerator.ShapeManager.register_consumer(handle)
            LoadGenerator.Stats.register_stat(:change)

            {row_id, handle, true, true}

          %Electric.Client.Message.ControlMessage{control: :up_to_date, handle: handle} ->
            if !registered?, do: LoadGenerator.ShapeManager.register_consumer(handle)
            LoadGenerator.Stats.register_stat(:up_to_date)
            {c, handle, monitored?, true}

          %Electric.Client.Message.ControlMessage{control: :must_refetch} ->
            # the handle is going to change so detach this pid from it
            # to keep the list of active shapes up-to-date
            LoadGenerator.Stats.register_stat(:refetch)
            :erlang.garbage_collect()
            LoadGenerator.ShapeManager.unregister_consumer()
            {c, nil, monitored?, false}

          msg ->
            Logger.warning(client: client_id, msg: inspect(msg))
            {c, handle, monitored?, registered?}
        end
      end)
    rescue
      e ->
        Logger.warning("client crashed: #{Exception.message(e)}")
        {:error, e}
    end
  end
end
