defmodule LoadGenerator.TableMutator do
  use GenServer

  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(args) do
    table = Keyword.fetch!(args, :table)
    column = Keyword.fetch!(args, :column)
    [type, alternate_type] = Keyword.fetch!(args, :types)
    frequency = Keyword.fetch!(args, :frequency)
    db = Keyword.get(args, :db, LoadGenerator.DB)

    state = %{
      table: table,
      column: column,
      type: type,
      alternate_type: alternate_type,
      frequency: frequency,
      db: db
    }

    {:ok, schedule_mutation(state)}
  end

  def handle_info(:mutate, state) do
    %{alternate_type: alternate_type, type: type, db: db, table: table, column: column} = state
    # dbg(mutate: {type, alternate_type})

    {time, _} =
      :timer.tc(
        fn ->
          LoadGenerator.DB.query!(
            db,
            ~s[ALTER TABLE "#{table}" ALTER "#{column}" TYPE #{alternate_type} USING mutating::#{alternate_type}],
            []
          )
        end,
        :millisecond
      )

    Logger.info("#{table}.#{column} #{type} -> #{alternate_type} (#{time}ms)")

    {:noreply, schedule_mutation(%{state | type: alternate_type, alternate_type: type})}
  end

  defp schedule_mutation(state) do
    Process.send_after(self(), :mutate, state.frequency)
    state
  end
end
