defmodule LoadGenerator.Client do
  use Task, restart: :transient

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

    Enum.reduce(stream, {0, nil, false}, fn msg, {c, handle, registered?} ->
      case msg do
        %Electric.Client.Message.ChangeMessage{
          value: %{"id" => row_id, "inserted_at" => _row_inserted_at},
          headers: %{operation: _operation, handle: handle},
          request_timestamp: _request_timestamp
        } ->
          if !registered?, do: LoadGenerator.ShapeManager.register_consumer(handle)
          {row_id, handle, true}

        %Electric.Client.Message.ControlMessage{control: :up_to_date} ->
          if rem(c, 100) == 0, do: Logger.debug(client: client_id, id: c)
          # IO.inspect(client: {client_id, :up_to_date})
          :erlang.garbage_collect()
          {c, handle, registered?}

        %Electric.Client.Message.ControlMessage{control: :must_refetch} ->
          # the handle is going to change so detach this pid from it
          # to keep the list of active shapes up-to-date
          LoadGenerator.Stats.register_stat(:refetch)
          :erlang.garbage_collect()
          LoadGenerator.ShapeManager.unregister_consumer()
          {c, nil, false}

          # msg ->
          #   Logger.warning(client: client_id, msg: inspect(msg))
          #   {c, up_to_date}
      end
    end)
  end
end
