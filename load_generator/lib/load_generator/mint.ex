defmodule LoadGenerator.Mint do
  # A Client.Pool implementation that opens a separate HTTP connection
  # for every client, rather than coalescing (as the default impl does)

  alias Electric.Client
  alias Electric.Client.Fetch

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
        raise "got status #{response.status}"

      error ->
        error
    end
  end

  @impl Electric.Client.Fetch
  def validate_opts(opts) do
    {:ok, opts}
  end

  @impl Electric.Client.Fetch
  def fetch(%Fetch.Request{} = request, opts) do
    with {:ok, conn} <- start_connection(request) do
      LoadGenerator.Mint.Connection.fetch(conn, request, opts)
    end
  end

  defp start_connection(%Fetch.Request{stream_id: stream_id} = _request) do
    DynamicSupervisor.start_child(
      Electric.Client.RequestSupervisor,
      {LoadGenerator.Mint.Connection, stream_id}
    )
    |> return_existing()
  end

  defp return_existing({:ok, pid}), do: {:ok, pid}
  defp return_existing({:error, {:already_started, pid}}), do: {:ok, pid}
  defp return_existing(error), do: error
end
