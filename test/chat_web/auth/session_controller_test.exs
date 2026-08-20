defmodule ChatWeb.SessionControllerTest do
  use ChatWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias Chat.Accounts

  setup do
    previous_login_module = Application.get_env(:chat, :auth_login_module)
    Application.put_env(:chat, :auth_login_module, Chat.AuthLoginStub)

    on_exit(fn ->
      Application.put_env(:chat, :auth_login_module, previous_login_module)
    end)

    {:ok, user} =
      Accounts.find_or_create_external_user(%{
        email: "session-user@jurunense.com",
        username: "session-user",
        matricula: "123",
        auth_provider: "external",
        auth_subject: "session-user"
      })

    %{user: user}
  end

  test "external login renews and stores the browser session", %{conn: conn} do
    conn = post(conn, ~p"/session", %{"username" => "alice", "password" => test_credential()})

    assert redirected_to(conn) == ~p"/home"
    assert get_session(conn, "user_id") == "03c82a75-5634-4362-a98c-32666ea319ca"
    assert conn.private.plug_session_info == :renew
  end

  test "an authenticated session mounts the protected chat", %{conn: conn, user: user} do
    conn =
      conn
      |> init_test_session(%{"user_id" => user.id})
      |> get(~p"/chat")

    assert html_response(conn, 200) =~ "session-user"
  end

  test "logout clears the browser session", %{conn: conn, user: user} do
    conn =
      conn
      |> init_test_session(%{"user_id" => user.id})
      |> delete(~p"/session")

    assert redirected_to(conn) == ~p"/"
    refute get_session(conn, "user_id")
  end

  test "invalid login gives a generic recovery message and preserves the username", %{conn: conn} do
    username = "invalid-user"
    password = test_credential()

    conn = post(conn, ~p"/session", %{"username" => username, "password" => password})

    assert redirected_to(conn) == ~p"/"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "Usuário ou senha incorretos. Tente novamente."

    assert Phoenix.Flash.get(conn.assigns.flash, :login_username) == username
    refute inspect(conn.assigns.flash) =~ password
  end

  test "authentication infrastructure failures log the internal reason without the password", %{
    conn: conn
  } do
    password = test_credential()

    log =
      capture_log(fn ->
        conn =
          post(conn, ~p"/session", %{
            "username" => "invalid-issuer",
            "password" => password
          })

        assert redirected_to(conn) == ~p"/"
      end)

    assert log =~ "authentication failed"
    assert log =~ "invalid_issuer"
    refute log =~ password
  end

  test "session cookie has explicit browser security controls" do
    endpoint = File.read!(Path.expand("../../../lib/chat_web/endpoint.ex", __DIR__))
    production = File.read!(Path.expand("../../../config/prod.exs", __DIR__))

    assert endpoint =~ "http_only: true"
    assert endpoint =~ "same_site: \"Lax\""
    assert endpoint =~ "max_age: 28_800"
    assert production =~ "secure_session_cookie: true"
  end

  defp test_credential do
    :crypto.strong_rand_bytes(24)
    |> Base.url_encode64(padding: false)
  end
end
