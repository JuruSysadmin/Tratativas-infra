defmodule Chat.Auth.AuthenticatorTest do
  use ExUnit.Case, async: true

  alias Chat.Accounts.User
  alias Chat.Auth.Authenticator

  test "returns a local Ecto user only after external JWT validation" do
    assert {:ok, %User{} = user, claims} =
             Authenticator.authenticate("valid-token",
               token_module: Chat.AuthTokenStub,
               identity_module: Chat.AuthIdentityStub
             )

    assert user.username == "alice"
    assert claims["sub"] == "alice"
  end

  test "rejects an invalid external JWT without local fallback" do
    assert {:error, :invalid_token} =
             Authenticator.authenticate("invalid-token",
               token_module: Chat.AuthTokenStub,
               identity_module: Chat.AuthIdentityStub
             )
  end
end
