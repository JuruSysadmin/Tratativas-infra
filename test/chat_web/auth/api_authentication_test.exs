defmodule ChatWeb.ApiAuthenticationTest do
  use ChatWeb.ConnCase, async: false

  alias Chat.Auth.Identity

  setup do
    {:ok, user} = Identity.sync_user(%{"sub" => "api-auth-user"}, %{})

    previous_module = Application.get_env(:chat, :authenticator_module)
    previous_pid = Application.get_env(:chat, :authenticator_spy_pid)
    previous_user = Application.get_env(:chat, :authenticator_spy_user)

    Application.put_env(:chat, :authenticator_module, Chat.AuthenticatorSpy)
    Application.put_env(:chat, :authenticator_spy_pid, self())
    Application.put_env(:chat, :authenticator_spy_user, user)

    on_exit(fn ->
      restore_env(:authenticator_module, previous_module)
      restore_env(:authenticator_spy_pid, previous_pid)
      restore_env(:authenticator_spy_user, previous_user)
    end)

    :ok
  end

  test "authenticates an API request exactly once", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer valid-token")
      |> get(~p"/api/rooms")

    assert json_response(conn, 200)
    assert_receive {:authenticated, "valid-token"}
    refute_receive {:authenticated, "valid-token"}
  end

  defp restore_env(key, nil), do: Application.delete_env(:chat, key)
  defp restore_env(key, value), do: Application.put_env(:chat, key, value)
end
