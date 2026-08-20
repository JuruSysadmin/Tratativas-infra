defmodule Chat.Auth.Login do
  @moduledoc false

  alias Chat.Auth.{External, Identity, Token}

  def authenticate(username, password, options \\ []) do
    request_options = Keyword.get(options, :request_options, [])
    token_module = Keyword.get(options, :token_module, Token)
    identity_module = Keyword.get(options, :identity_module, Identity)

    with {:ok, token, response} <- External.request_token(username, password, request_options),
         {:ok, claims} <- token_module.validate_jwks_token(token),
         {:ok, user} <- identity_module.sync_user(claims, response) do
      {:ok, user, token, response}
    end
  end
end
