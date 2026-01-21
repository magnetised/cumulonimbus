defmodule LoadGenerator.Mint do
  # A Client.Pool implementation that opens a separate HTTP connection
  # for every client, rather than coalescing (as the default impl does)

  alias Electric.Client
  alias Electric.Client.Fetch

  require Logger

  @behaviour Electric.Client.Fetch.Pool
  @behaviour Electric.Client.Fetch

  def client(attrs) do
    Client.new(
      Keyword.merge(attrs,
        pool: {__MODULE__, []},
        fetch: {__MODULE__, []}
      )
    )
  end

  @impl Electric.Client.Fetch.Pool
  def request(%Client{} = client, %Fetch.Request{} = request, _opts) do
    %{fetch: {fetcher, fetcher_opts}} = client
    authenticated_request = Client.authenticate_request(client, request)

    case fetcher.fetch(authenticated_request, fetcher_opts) do
      {:ok, %Fetch.Response{status: status} = response} when status in 200..299 ->
        response

      {:ok, %Fetch.Response{status: 409} = response} ->
        {:error, response}

      # want to just raise if we don't get a good response
      {:ok, %Fetch.Response{} = response} ->
        Logger.error(status: response.status, body: response.body)
        # raise "got status #{response.status}"

        {:error, response}

      error ->
        error
    end
  end

  @impl Electric.Client.Fetch
  def validate_opts(opts) do
    {:ok, opts}
  end

  @impl Electric.Client.Fetch
  def fetch(%Fetch.Request{} = request, _opts) do
    uri = Fetch.Request.uri(request, query: true)
    conn = open(uri)

    with {:ok, conn, request_ref} <-
           Mint.HTTP.request(
             conn,
             String.upcase(to_string(request.method)),
             "#{uri.path}?#{uri.query}",
             Enum.map(request.headers, fn {k, v} -> {to_string(k), to_string(v)} end),
             nil
           ) do
      :telemetry.execute([:client, :http_request], %{})

      receive_request(conn, request_ref, %Fetch.Response{body: []})
    end
  end

  def open(uri) do
    if conn = Process.get({__MODULE__, :conn}) do
      conn
    else
      {:ok, conn} = Mint.HTTP1.connect(String.to_atom(uri.scheme), uri.host, uri.port)
      Process.put({__MODULE__, :conn}, conn)
      conn
    end
  end

  def receive_request(conn, ref, response) do
    receive do
      message ->
        case Mint.HTTP.stream(conn, message) do
          {:ok, conn, responses} ->
            Enum.reduce(responses, response, fn
              {:status, ^ref, status}, response ->
                %{response | status: status}

              {:headers, ^ref, headers}, response ->
                %{response | headers: Map.new(headers)}

              {:data, ^ref, data}, response ->
                %{response | body: [response.body | data]}

              {:done, ^ref}, response ->
                {:halt, response}
            end)
            |> case do
              %Fetch.Response{} = response ->
                receive_request(conn, ref, response)

              {:halt, response} ->
                response
                |> Fetch.Response.decode!()
                |> finalise()
            end
        end
    end
  end

  defp finalise(%Fetch.Response{body: iodata} = response) do
    case iodata
         |> IO.iodata_to_binary()
         |> tap(fn body ->
           LoadGenerator.Stats.register_stat(:bytes, byte_size(body))
         end)
         |> Jason.decode() do
      {:ok, body} ->
        {:ok, %{response | body: body}}

      {:error, _} ->
        {:ok, %{response | body: IO.iodata_to_binary(iodata)}}
    end
  end

  defp return_existing({:ok, pid}), do: {:ok, pid}
  defp return_existing({:error, {:already_started, pid}}), do: {:ok, pid}
  defp return_existing(error), do: error
end
