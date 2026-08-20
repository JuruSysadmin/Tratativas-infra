defmodule ChatWeb.ChatState do
  @moduledoc """
  Orquestração de estado do LiveView de chat.

  Agrupa inicialização, seleção e limpeza de sala combinando módulos
  especializados.
  """

  use Phoenix.LiveView

  alias Chat.Messages
  alias Chat.Rooms
  alias ChatWeb.ChatMessages
  alias ChatWeb.ChatNotifications
  alias ChatWeb.ChatPresence
  alias ChatWeb.RoomNavigation
  alias ChatWeb.TypingManager

  @doc """
  Inicializa o estado completo do chat.
  """
  def init(socket) do
    socket
    |> RoomNavigation.init()
    |> ChatMessages.init()
    |> ChatNotifications.init()
    |> ChatPresence.init()
    |> TypingManager.init()
    |> assign(:input_text, "")
    |> assign(:mention_suggestions, [])
  end

  @doc """
  Seleciona uma sala e prepara seu estado.
  """
  def select_room(socket, room, opts \\ []) do
    user_id = socket.assigns.current_user.id

    case Rooms.with_member_room(user_id, room.id, fn authorized_room ->
           select_authorized_room(socket, authorized_room, opts)
         end) do
      {:ok, {selected_socket, true}} ->
        Chat.Broadcaster.broadcast_read_receipts_updated(
          room.id,
          user_id,
          selected_socket.assigns.message_order,
          from: self()
        )

        Chat.Broadcaster.broadcast_mention_state_changed(user_id, room.id)
        selected_socket

      {:ok, {selected_socket, false}} ->
        selected_socket

      {:error, _reason} ->
        revoke_room_access(socket, room.id)
    end
  end

  defp select_authorized_room(socket, room, opts) do
    socket =
      socket
      |> ChatPresence.leave()
      |> assign(:current_room, room)
      |> ChatMessages.load_room(room, through: Keyword.get(opts, :through))
      |> assign(:input_text, "")
      |> assign(:mention_suggestions, [])

    user_id = socket.assigns.current_user.id

    position_advanced? =
      match?(
        {:ok, _position},
        Messages.advance_room_read_position(user_id, room.id, socket.assigns.message_order)
      )

    selected_socket =
      socket
      |> ChatPresence.init()
      |> assign(:navigation_open, false)
      |> ChatWeb.UnreadTracking.refresh(room.id)
      |> ChatPresence.join(room)
      |> ChatPresence.refresh_online_users()
      |> ChatMessages.refresh_statuses()
      |> refresh_mentions()

    {selected_socket, position_advanced?}
  end

  def refresh_mentions(socket) do
    ChatNotifications.refresh(socket)
  end

  def revoke_room_access(socket, room_id) do
    socket
    |> ChatWeb.PubSubManager.unsubscribe(room_id)
    |> RoomNavigation.refresh()
    |> clear_selected_room(room_id)
    |> refresh_mentions()
  end

  @doc """
  Limpa a sala selecionada quando o usuário sai.
  """
  def clear_selected_room(socket, room_id) do
    case socket.assigns.current_room do
      %{id: ^room_id} ->
        socket
        |> ChatPresence.leave()
        |> assign(:current_room, nil)
        |> ChatMessages.clear()
        |> ChatPresence.init()

      _room ->
        socket
    end
  end
end
