defmodule Chat.Auth.IdentityCacheTest do
  use ExUnit.Case, async: false

  alias Chat.Accounts.User
  alias Chat.Auth.IdentityCache

  setup do
    Application.put_env(:chat, :auth_identity_cache_ttl_ms, 40)
    IdentityCache.clear()

    on_exit(fn ->
      Application.delete_env(:chat, :auth_identity_cache_ttl_ms)
      IdentityCache.clear()
    end)

    :ok
  end

  test "stores and returns a user until the TTL expires" do
    user = %User{id: Ecto.UUID.generate(), username: "cache-user"}

    assert :miss = IdentityCache.get("external", "ttl-sub")
    assert :ok = IdentityCache.put("external", "ttl-sub", user, "fp-1")
    assert {:ok, ^user, "fp-1"} = IdentityCache.get("external", "ttl-sub")

    Process.sleep(50)

    assert :miss = IdentityCache.get("external", "ttl-sub")
  end
end
