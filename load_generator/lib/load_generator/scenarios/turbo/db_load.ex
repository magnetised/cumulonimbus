defmodule LoadGenerator.Turbo.DbLoad do
  use Task, restart: :transient

  require Logger

  def child_spec(arg) do
    %{
      id: {__MODULE__, arg[:id] || 1},
      start: {__MODULE__, :start_link, [arg]},
      restart: :transient
    }
  end

  def start_link(args) do
    Task.start_link(__MODULE__, :run, [args])
  end

  defmodule Fast do
    def init(tps) do
      {__MODULE__, %{start: now(), tps: tps, n: 0}}
    end

    def insert?(%{start: start, tps: tps, n: n} = state) do
      now = now()
      age = (now - start) / 1000
      probability = age * tps

      if :rand.uniform_real() <= probability do
        {true, n + 1, %{state | start: now, n: n + 1}}
      else
        {false, n, state}
      end
    end

    defp now, do: System.monotonic_time(:millisecond)
  end

  defmodule Slow do
    def init(tps) do
      {__MODULE__, %{start: now(), tps: tps, n: 0}}
    end

    def insert?(%{start: start, tps: tps, n: n} = state) do
      now = now()
      age = (now - start) / 1000
      expected_inserts = round(age * tps)
      diff = expected_inserts - n

      if diff > 0 do
        {true, n + 1, %{state | n: n + 1}}
      else
        {false, n, state}
      end
    end

    defp now, do: System.monotonic_time(:millisecond)
  end

  def run(opts) do
    db = Keyword.get(opts, :db, LoadGenerator.DB)
    table = Keyword.fetch!(opts, :table)
    streams = Keyword.fetch!(opts, :streams)
    max_rows = Keyword.fetch!(opts, :max_rows)
    rows_per_partition = Keyword.fetch!(opts, :rows_per_partition)

    duration =
      case Keyword.get(opts, :duration, :infinity) do
        seconds when is_integer(seconds) -> seconds * 1000
        :infinity -> :infinity
      end

    [fast_tps, slow_tps] = Keyword.get(opts, :tps, [1, 1])

    batch_size = 5
    threads = ceil(fast_tps / batch_size)

    {:ok, collector} =
      Task.start_link(fn ->
        receive_tx(0, System.monotonic_time(:millisecond), duration)
      end)

    rows_per_thread = div(max_rows, threads)

    {tasks, _} =
      Enum.map_reduce(
        1..threads,
        {fast_tps, slow_tps, max_rows},
        fn p, {remaining_ftps, remaining_stps, insert_rows} ->
          fast_tps = min(remaining_ftps, batch_size)
          slow_tps = min(remaining_stps, batch_size)

          task =
            Task.async(fn ->
              test = Fast.init(fast_tps)

              Enum.reduce(streams, test, fn {id, partition_stream}, test ->
                insert_partition = Enum.random(rows_per_partition)

                {test, _} =
                  Enum.reduce_while(partition_stream, {test, 0}, fn row, {test, c} ->
                    {module, state} = test
                    {insert?, n, state} = module.insert?(state)

                    if insert? do
                      LoadGenerator.DB.insert!(table, row, db)

                      value = inspect(row)

                      send(
                        collector,
                        {:txn, p, n, [binary_part(value, 0, min(byte_size(value), 32)), "..."],
                         byte_size(value)}
                      )

                      if n >= insert_rows do
                        test = Slow.init(slow_tps)
                        {:cont, {test, c + 1}}
                      else
                        {:cont, {{module, state}, c + 1}}
                      end
                    else
                      if c >= insert_partition do
                        :erlang.garbage_collect()
                        {:halt, {test, 0}}
                      else
                        Process.sleep(1)
                        {:cont, {test, c}}
                      end
                    end
                  end)

                test
              end)
            end)

          {task,
           {remaining_ftps - fast_tps, remaining_stps - slow_tps,
            max(insert_rows - rows_per_thread, 0)}}
        end
      )

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
