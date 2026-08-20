defmodule ChatWeb.ChatRooms do
  @moduledoc """
  Gerenciamento de salas, navegação e subscriptions PubSub no chat.
  """
  @deprecated "Use ChatWeb.RoomNavigation, ChatWeb.UnreadTracking, ChatWeb.PubSubManager, or ChatWeb.RoomManagement directly"

  alias ChatWeb.RoomManagement

  defdelegate init(socket), to: ChatWeb.RoomNavigation
  defdelegate refresh(socket), to: ChatWeb.RoomNavigation
  defdelegate open_new_room_dialog(socket), to: ChatWeb.RoomNavigation, as: :open_new_dialog
  defdelegate open_room_explorer(socket), to: ChatWeb.RoomNavigation, as: :open_explorer
  defdelegate close_dialog(socket), to: ChatWeb.RoomNavigation
  defdelegate search(socket, query), to: ChatWeb.RoomNavigation, as: :search_available
  defdelegate clear_search(socket), to: ChatWeb.RoomNavigation
  defdelegate find_assigned_room(socket, room_id), to: ChatWeb.RoomNavigation

  defdelegate create(socket, room_params, user_id), to: RoomManagement
  defdelegate join(socket, room_id, user_id), to: RoomManagement
  defdelegate leave(socket, room_id, user_id), to: RoomManagement
  defdelegate confirm_delete(socket, room_id, user_id), to: RoomManagement
  defdelegate delete(socket, room_id, user_id), to: RoomManagement

  defdelegate increment_unread(socket, room_id), to: ChatWeb.UnreadTracking, as: :increment
  defdelegate clear_unread(socket, room_id), to: ChatWeb.UnreadTracking, as: :clear
  defdelegate refresh_unread(socket, room_id), to: ChatWeb.UnreadTracking, as: :refresh

  defdelegate subscribe(socket, room), to: ChatWeb.PubSubManager
  defdelegate unsubscribe(socket, room_id), to: ChatWeb.PubSubManager
end
