defmodule ChatWeb.UserSocket do
  use Phoenix.Socket

  alias Chat.Auth.Authenticator

  channel "room:*", ChatWeb.RoomChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Authenticator.authenticate(token) do
      {:ok, user, claims} ->
        {:ok,
         socket
         |> assign(:current_user, user)
         |> assign(:user_claims, claims)}

      {:error, _reason} ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket) do
    "user_socket:#{socket.assigns.current_user.id}"
  end
end
