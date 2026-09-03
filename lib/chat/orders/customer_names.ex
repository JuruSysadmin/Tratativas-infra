defmodule Chat.Orders.CustomerNames do
  @moduledoc """
  TTL cache for order customer names resolved from the orders API.

  Customer names are stable business data, but the orders API is queried one
  order at a time. Caching them keeps queue views (which list up to 100
  treatments per request, refreshing periodically) from issuing one external
  request per treatment on every load.
  """

  use GenServer

  alias Chat.Orders.Client

  @table :orders_customer_names
  @default_ttl_ms :timer.hours(1)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Resolves customer names for the given order ids, serving fresh cache entries
  and fetching only the misses concurrently.

  Orders that cannot be resolved (lookup failure, missing authorization header)
  are absent from the result.
  """
  @spec resolve([integer()] | integer(), String.t() | nil) :: %{integer() => String.t()}
  def resolve(order_ids, authorization_header) do
    ids =
      order_ids
      |> List.wrap()
      |> Enum.uniq()
      |> Enum.filter(&is_integer/1)

    {cached_names, missing_ids} =
      ids
      |> Enum.map(&{&1, cached_name(&1)})
      |> Enum.split_with(fn {_id, name} -> is_binary(name) end)

    fetched_names = fetch_missing(Enum.map(missing_ids, &elem(&1, 0)), authorization_header)

    Map.merge(Map.new(cached_names), fetched_names)
  end

  defp cached_name(order_id) do
    case :ets.lookup(@table, order_id) do
      [{^order_id, {name, fetched_at_ms}}] ->
        if monotonic_ms() - fetched_at_ms < ttl_ms(), do: name, else: nil

      [] ->
        nil
    end
  end

  defp fetch_missing(missing_ids, authorization_header) do
    if missing_ids == [] or not is_binary(authorization_header) do
      %{}
    else
      missing_ids
      |> Client.get_many(authorization_header)
      |> Map.new(fn {order_id, summary} ->
        :ets.insert(@table, {order_id, {summary.customer_name, monotonic_ms()}})
        {order_id, summary.customer_name}
      end)
    end
  end

  defp ttl_ms, do: Application.get_env(:chat, :orders_customer_names_ttl_ms, @default_ttl_ms)

  defp monotonic_ms, do: System.monotonic_time(:millisecond)

  @impl true
  def init(_) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    {:ok, nil}
  end
end
