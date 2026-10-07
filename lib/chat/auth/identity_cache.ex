defmodule Chat.Auth.IdentityCache do
  @moduledoc """
  Short-lived ETS cache for externally authenticated users.

  JWT validation still runs on every request; this cache only avoids repeating
  `Accounts.find_or_create_external_user/1` when claims fingerprint is unchanged.
  """

  use GenServer

  @table :auth_identity_cache
  @default_ttl_ms :timer.seconds(60)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec get(String.t(), String.t()) :: {:ok, Chat.Accounts.User.t(), String.t()} | :miss
  def get(provider, subject)
      when is_binary(provider) and is_binary(subject) do
    now = monotonic_ms()

    case :ets.lookup(@table, {provider, subject}) do
      [{_key, {user, fingerprint, expires_at}}] when expires_at > now ->
        {:ok, user, fingerprint}

      _other ->
        :miss
    end
  end

  @spec put(String.t(), String.t(), Chat.Accounts.User.t(), String.t()) :: :ok
  def put(provider, subject, user, fingerprint)
      when is_binary(provider) and is_binary(subject) and is_binary(fingerprint) do
    expires_at = monotonic_ms() + ttl_ms()
    true = :ets.insert(@table, {{provider, subject}, {user, fingerprint, expires_at}})
    :ok
  end

  @spec delete(String.t(), String.t()) :: :ok
  def delete(provider, subject)
      when is_binary(provider) and is_binary(subject) do
    :ets.delete(@table, {provider, subject})
    :ok
  end

  @spec clear() :: :ok
  def clear do
    :ets.delete_all_objects(@table)
    :ok
  end

  @impl true
  def init(_) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    {:ok, nil}
  end

  defp ttl_ms, do: Application.get_env(:chat, :auth_identity_cache_ttl_ms, @default_ttl_ms)

  defp monotonic_ms, do: System.monotonic_time(:millisecond)
end
