defmodule Chat.Auth.JwksStrategyTest do
  use ExUnit.Case, async: true

  alias Chat.Auth.JwksStrategy

  test "uses the Finch instance already started by Req to fetch JWKS keys" do
    opts = JwksStrategy.init_opts([])

    assert opts[:http_adapter] == {Tesla.Adapter.Finch, name: Req.Finch}
  end

  test "fetches JWKS synchronously before the first login attempt" do
    opts = JwksStrategy.init_opts([])

    assert opts[:first_fetch_sync] == true
    assert opts[:should_start] == true
  end
end
