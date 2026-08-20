defmodule Chat.Auth.ExternalTest do
  use ExUnit.Case, async: true

  alias Chat.Auth.External

  test "requests an access token from the configured external provider" do
    password = random_test_credential()

    plug = fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert Jason.decode!(body) == %{"password" => password, "username" => "alice"}

      Req.Test.json(conn, %{
        token: "signed-rs256-token",
        username: "Alice",
        expiresIn: 900
      })
    end

    assert {:ok, "signed-rs256-token", response} =
             External.request_token("alice", password, plug: plug)

    assert response["username"] == "Alice"
  end

  test "maps invalid credentials without exposing provider details" do
    plug = fn conn -> conn |> Plug.Conn.send_resp(401, "") end

    assert {:error, :invalid_credentials} =
             External.request_token("alice", random_test_credential(), plug: plug)
  end

  defp random_test_credential do
    :crypto.strong_rand_bytes(24)
    |> Base.url_encode64(padding: false)
  end
end
