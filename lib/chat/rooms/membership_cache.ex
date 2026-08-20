defmodule Chat.Rooms.MembershipCache do
  @moduledoc "ETS-based cache for room membership lookups."

  use GenServer

  @table :room_membership_cache

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def get(user_id, room_id) do
    case :ets.lookup(@table, {user_id, room_id}) do
      [{_key, value}] -> value
      [] -> nil
    end
  end

  def put(user_id, room_id, value) do
    :ets.insert(@table, {{user_id, room_id}, value})
    :ok
  end

  def delete(user_id, room_id) do
    :ets.delete(@table, {user_id, room_id})
    :ok
  end

  @impl true
  def init(_) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    {:ok, nil}
  end
end
