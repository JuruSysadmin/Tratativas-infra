defmodule Chat.Auth.Authenticator do
  @moduledoc false

  alias Chat.Accounts.User
  alias Chat.Auth.{Identity, Token}

  def authenticate(token, options \\ []) do
    token_module = Keyword.get(options, :token_module, Token)
    identity_module = Keyword.get(options, :identity_module, Identity)

    with {:ok, claims} <- token_module.validate_jwks_token(token),
         {:ok, %User{} = user} <- identity_module.sync_user(claims, %{}) do
      {:ok, user, claims}
    end
  end
end
