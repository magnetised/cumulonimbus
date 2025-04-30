defmodule LoadGenerator.DbLoad do
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

  def run(opts) do
    db = Keyword.get(opts, :db, LoadGenerator.DB)
    table = Keyword.fetch!(opts, :table)
    stream = Keyword.fetch!(opts, :stream)
    # reset = Keyword.get(opts, :reset, false)

    duration =
      case Keyword.get(opts, :duration, :infinity) do
        seconds when is_integer(seconds) -> seconds * 1000
        :infinity -> :infinity
      end

    tps = Keyword.get(opts, :tps, 1)
    batch_size = 5
    threads = ceil(tps / batch_size)
    # stream = LoadGenerator.row_stream(columns, :binary)

    # if reset do
    #   IO.puts(IO.ANSI.format([:red, "Deleting all data in #{table}\n"]))
    #   LoadGenerator.DB.reset!(db, table)
    # end

    {:ok, collector} =
      Task.start_link(fn ->
        receive_tx(0, System.monotonic_time(:millisecond), duration)
      end)

    {tasks, _} =
      Enum.map_reduce(1..threads, tps, fn p, remaining_tps ->
        tps = min(remaining_tps, batch_size)

        task =
          Task.async(fn ->
            start = System.monotonic_time(:millisecond)

            Enum.reduce(stream, {start, 0, 0}, fn row, {start, n, c} ->
              now = System.monotonic_time(:millisecond)
              age = (now - start) / 1000
              probability = age * tps

              # diff = expected_inserts - n

              if :rand.uniform_real() <= probability do
                n = n + 1
                LoadGenerator.DB.insert!(table, row, db)

                value = inspect(row)

                send(
                  collector,
                  {:txn, p, n, [binary_part(value, 0, min(byte_size(value), 32)), "..."],
                   byte_size(value)}
                )

                {now, n, c + 1}
              else
                if c >= 100 do
                  :erlang.garbage_collect()
                  {start, n, 0}
                else
                  Process.sleep(1)
                  {start, n, c}
                end
              end
            end)
          end)

        {task, remaining_tps - tps}
      end)

    try do
      Task.await_many(tasks, duration)
    catch
      _, _ ->
        Enum.each(tasks, &Task.shutdown(&1, :brutal_kill))
        :ok
    end
  end

  defp receive_tx(n, start, duration) do
    receive do
      {:txn, _p, _n, value, _size} ->
        LoadGenerator.Stats.register_stat(:insert_row)
        now = System.monotonic_time(:millisecond)
        n = n + 1

        # remaining =
        #   case duration do
        #     duration when is_integer(duration) ->
        #       remaining = (duration - (now - start)) / 1000 / 60
        #       mins = floor(remaining)
        #       seconds = round((remaining - mins) * 60)
        #       "remaining #{mins}m #{seconds}s"
        #
        #     :infinity ->
        #       ""
        #   end

        Logger.debug(
          insert: n,
          value: inspect(value, limit: :infinity),
          tps: Float.round(n / ((now - start) / 1000), 2)
        )

        # IO.puts([
        #   "#{n} #{remaining} #{Float.round(n / ((now - start) / 1000), 2)}tps - ",
        #   value,
        #   " ",
        #   to_string(size),
        #   "b"
        # ])

        receive_tx(n, start, duration)
    end
  end
end
