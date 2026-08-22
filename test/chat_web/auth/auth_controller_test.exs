defmodule ChatWeb.AuthControllerTest do
  use ChatWeb.ConnCase, async: false

  alias Chat.Accounts.User

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

  test "authenticated Chat identity exposes only id and role", %{conn: conn} do
    user = %User{id: "550e8400-e29b-41d4-a716-446655440000", role: "logistics_agent"}

    conn =
      conn
      |> assign(:current_user, user)
      |> ChatWeb.AuthController.me(%{})

    assert %{
             "user" => %{
               "id" => "550e8400-e29b-41d4-a716-446655440000",
               "role" => "logistics_agent"
             }
           } =
             json_response(conn, 200)
  end

  test "Chat identity endpoint requires authentication", %{conn: conn} do
    conn = get(conn, ~p"/api/auth/me")

    assert response(conn, 401)
  end

  defp test_credential do
    :crypto.strong_rand_bytes(24)
    |> Base.url_encode64(padding: false)
  end
end
