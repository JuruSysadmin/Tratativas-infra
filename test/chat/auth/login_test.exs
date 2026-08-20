defmodule Chat.Auth.LoginTest do
  use Chat.DataCase, async: true

  alias Chat.Accounts.User
  alias Chat.Auth.Login

  test "creates a local user only after validating the provider token" do
    plug = fn conn ->
      Req.Test.json(conn, %{
        token: "valid-token",
        username: "Alice",
        expiresIn: 900
      })
    end

    assert {:ok, %User{} = user, "valid-token", response} =
             Login.authenticate("alice", "secret",
               request_options: [plug: plug],
               token_module: Chat.AuthTokenStub
             )

    assert user.username == "Alice"
    assert response["expiresIn"] == 900
  end
end
