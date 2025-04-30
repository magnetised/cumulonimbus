defmodule LoadGenerator.Stats do
  use GenServer

  require Logger

  @period 10_000

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def register_stat(type, count \\ 1) do
    GenServer.cast(__MODULE__, {:register, type, count})
  end

  def init(_args) do
    # could probably use an ets counter table but no need for perf reasons atm
    state = %{stats: %{}, start: DateTime.utc_now()}
    # trap exits to trigger terminate/2 to flush the stats on exit
    Process.flag(:trap_exit, true)
    {:ok, schedule_log(state)}
  end

  def terminate(_reason, state) do
    log(state)
  end

  def handle_cast({:register, type, count}, state) do
    stats = Map.update(state.stats, type, count, &(&1 + count))
    {:noreply, %{state | stats: stats}}
  end

  def handle_info(:log, state) do
    {:noreply, state |> log() |> schedule_log()}
  end

  defp schedule_log(state) do
    Process.send_after(self(), :log, @period)
    state
  end

  defp log(state) do
    duration = DateTime.diff(DateTime.utc_now(), state.start, :second)
    Logger.info(Map.merge(state.stats, %{duration: duration}))
    state
  end
end
