Mix.install([:statistics])

filter = fn filename ->
  grep = ~r/\[(?:unregister|register)_reader: (\d+)]/

  filename
  |> File.stream!()
  |> Stream.map(&String.trim/1)
  |> Enum.flat_map(fn line ->
    case Regex.run(grep, line) do
      nil -> []
      [_, time] -> [String.to_integer(time)]
    end
  end)
end

percentile = fn times, n ->
  Statistics.percentile(times, n)
end

files = Path.wildcard("stats*.txt")
p = [50, 95, 99, 99.9]

indent = "  "

Enum.map(files, fn file ->
  times = filter.(file)
  IO.puts([file, "..."])

  stats =
    Map.new(p, fn n ->
      {n, percentile.(times, n)}
    end)

  {file, times, stats}
end)
|> Enum.sort_by(fn {_file, _times, stats} -> stats[99] end)
|> Enum.each(fn {file, times, stats} ->
  IO.puts(["\n", file, "  [", to_string(length(times)), " measurements]", ":"])

  for {p, m} <- stats do
    IO.puts([indent, indent, "p", to_string(p), ": ", to_string(m), " us"])
  end
end)
