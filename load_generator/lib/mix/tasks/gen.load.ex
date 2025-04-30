defmodule Mix.Tasks.Gen.Load do
  use Mix.Task

  @shortdoc "Generate Load"
  @doc """
  ## mix gen.load

  - Table should exist and schema should match the column spec.

  ### Arguments

  - `table` - the table name in the database.
  - `db` - URI of the database, defaults to: `postgresql://postgres:password@localhost:5432/electric`
  - `column` - column generator specification. Can be given multiple times
  - `tps` - how many transactions per second to generate (default `1`)
  - `reset` - delete existing data from `table` before generating new data.
  - `duration` - how long to run for (in seconds)

  ## Columns

  Columns are specified as `name[:type[:size]]`.

  If not specified, `type` defaults to `text` and `size` to `10..128` bytes.

  `type` can be `text`, `integer` or `uuid`.

  `size` can be a fixed number of bytes, e.g. `123` or a range, e.g. `1..1000`.
  If given as a range, the generated size will be picked randomly from that
  range.

  For `text` columns, the size specifies the number of bytes in the value, for
  `integer` types, the size defines the value of the column.

  For `uuid` types, the size is ignored.

  ## Examples


      mix gen.load --table "items" --db "$DATABASE_URL" --column "id:uuid" --column "value:text:128" --tps 10
      # -c is equivalent to --column
      mix gen.load --table "items" --db "$DATABASE_URL" -c "id:uuid" -c "value:text:128" --tps 10

  """
  def run(argv) do
    {:ok, _apps} = Application.ensure_all_started(:load_generator)

    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [
          db: :string,
          table: :string,
          # examples:
          #   id:uuid
          #   name (-> name:string:10..128)
          #   name:string (-> name:string:10..128)
          #   name:string:0..1024
          #   count:integer:3
          column: [:string, :keep],
          reset: :boolean,
          duration: :integer,
          tps: :integer
        ],
        aliases: [c: :column, p: :partition]
      )

    column_specs = Keyword.get_values(opts, :column)
    columns = Enum.map(column_specs, &LoadGenerator.Column.parse_spec!/1)

    LoadGenerator.DbLoad.run(Keyword.put(opts, :columns, columns))
  end
end
