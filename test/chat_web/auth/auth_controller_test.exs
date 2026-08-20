defmodule ChatWeb.AuthControllerTest do
  use ChatWeb.ConnCase, async: false

  setup do
    previous_login_module = Application.get_env(:chat, :auth_login_module)
    Application.put_env(:chat, :auth_login_module, Chat.AuthLoginStub)

    on_exit(fn -> Application.put_env(:chat, :auth_login_module, previous_login_module) end)
  end

  test "API login returns the externally signed token", %{conn: conn} do
    conn = post(conn, ~p"/api/auth/login", %{username: "alice", password: test_credential()})

    assert %{"token" => "valid-token", "user" => %{"username" => "alice"}} =
             json_response(conn, 200)

    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  test "local registration is not exposed", %{conn: conn} do
    conn =
      post(conn, "/api/auth/register", %{
        user: %{email: "local@example.com", username: "local", password: test_credential()}
      })

    assert response(conn, 404)
  end

  defp test_credential do
    :crypto.strong_rand_bytes(24)
    |> Base.url_encode64(padding: false)
  end
end
