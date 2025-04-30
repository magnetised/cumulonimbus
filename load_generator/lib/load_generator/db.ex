defmodule LoadGenerator.DB do
  def child_spec(url) do
    %{id: {__MODULE__, url}, start: {__MODULE__, :start_link, [url]}}
  end

  def start_link(opts) when is_list(opts) do
    db_url = Keyword.fetch!(opts, :db)
    pool_size = Keyword.get(opts, :pool_size, 20)
    start_link(db_url, pool_size)
  end

  def start_link(url, pool_size \\ 20) do
    connection_config = PostgresqlUri.parse(url)

    Postgrex.start_link(connection_config ++ [pool_size: pool_size, name: __MODULE__])
  end

  def insert_query(table, row) do
    [columns, placeholders, values] =
      row
      |> Enum.with_index(1)
      |> Enum.map(fn {{column, value}, n} -> [column, "$#{n}", value] end)
      |> Enum.zip()
      |> Enum.map(&Tuple.to_list/1)

    {
      IO.iodata_to_binary([
        "INSERT INTO ",
        ?",
        table,
        ?",
        " (",
        Enum.map_intersperse(columns, ", ", &[?", &1, ?"]),
        ") VALUES (",
        Enum.intersperse(placeholders, ", "),
        ")"
      ]),
      values
    }
  end

  def insert!(table, row, pool \\ __MODULE__) do
    {query, params} = insert_query(table, row)
    query!(pool, query, params)
  end

  def query!(pool \\ __MODULE__, query, params) do
    Postgrex.query!(pool, query, params)
  end

  def reset!(pool \\ __MODULE__, table) do
    query!(pool, ~s[DELETE FROM "#{table}"], [])
  end
end
