defmodule ChatWeb.UserSocketTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Chat.Accounts.User
  alias ChatWeb.UserSocket

  defmodule AuthOk do
    def authenticate("good-token") do
      user = %User{id: Ecto.UUID.generate(), username: "socket-user", role: "commercial"}
      {:ok, user, %{"sub" => "socket-user"}}
    end

    def authenticate(_token), do: {:error, :token_expired}
  end

  setup do
    previous = Application.get_env(:chat, :authenticator_module)
    Application.put_env(:chat, :authenticator_module, AuthOk)

    on_exit(fn ->
      if previous do
        Application.put_env(:chat, :authenticator_module, previous)
      else
        Application.delete_env(:chat, :authenticator_module)
      end
    end)

    :ok
  end

  test "connect succeeds with a valid authenticated user" do
    assert {:ok, socket} =
             UserSocket.connect(%{"token" => "good-token"}, %Phoenix.Socket{}, %{})

    assert socket.assigns.current_user.username == "socket-user"
  end

  test "connect logs the auth failure reason without accepting the socket" do
    log =
      capture_log(fn ->
        assert :error =
                 UserSocket.connect(%{"token" => "expired-token"}, %Phoenix.Socket{}, %{})
      end)

    assert log =~ "user_socket_connect_refused"
    assert log =~ "token_expired"
  end

  test "connect logs missing_token when params have no token" do
    log =
      capture_log(fn ->
        assert :error = UserSocket.connect(%{}, %Phoenix.Socket{}, %{})
      end)

    assert log =~ "user_socket_connect_refused"
    assert log =~ "missing_token"
  end
end
