defmodule Chat.Auth.JwksStrategy do
  @moduledoc """
  JWKS fetching strategy for JokenJwks.
  Fetches and caches public keys from the auth-server JWKS endpoint.
  """

  use JokenJwks.DefaultStrategyTemplate

  def init_opts(opts) do
    auth_config = Application.get_env(:chat, :auth, [])

    Keyword.merge(opts,
      jwks_url: auth_config[:jwks_url] || auth_config[:jwks_uri],
      http_adapter: {Tesla.Adapter.Finch, name: Req.Finch},
      explicit_alg: "RS256",
      time_interval: 60_000,
      first_fetch_sync: true,
      should_start: true
    )
  end
end
