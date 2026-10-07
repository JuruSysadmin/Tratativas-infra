defmodule ChatWeb.UserSocket do
  @moduledoc "Phoenix socket entry point for authenticated user connections."

  use Phoenix.Socket

  require Logger

  alias Chat.Auth.Authenticator

  channel "room:*", ChatWeb.RoomChannel
  channel "treatments:queue", ChatWeb.TreatmentQueueChannel
  channel "user:*", ChatWeb.UserChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) when is_binary(token) and token != "" do
    authenticator = Application.get_env(:chat, :authenticator_module, Authenticator)

    case authenticator.authenticate(token) do
      {:ok, user, claims} ->
        {:ok,
         socket
         |> assign(:current_user, user)
         |> assign(:user_claims, claims)}

      {:error, reason} ->
        Logger.warning("user_socket_connect_refused reason=#{inspect(reason)}")
        :error
    end
  end

  def connect(_params, _socket, _connect_info) do
    Logger.warning("user_socket_connect_refused reason=:missing_token")
    :error
  end

  @impl true
  def id(socket) do
    "user_socket:#{socket.assigns.current_user.id}"
  end
end
