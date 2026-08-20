defmodule ChatWeb.ChatLiveAuthorizationTest do
  use Chat.DataCase, async: true

  import Phoenix.Component, only: [assign: 2]

  alias Chat.Auth.Identity
  alias Chat.Messages
  alias Chat.Rooms
  alias ChatWeb.ChatLive

  setup do
    {:ok, owner} = Identity.sync_user(%{"sub" => "live-owner"}, %{})
    {:ok, outsider} = Identity.sync_user(%{"sub" => "live-outsider"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Protegida"}, owner.id)

    socket =
      %Phoenix.LiveView.Socket{private: %{lifecycle: %Phoenix.LiveView.Lifecycle{}}}
      |> assign(%{
        current_user: outsider,
        current_room: nil,
        message_ids: MapSet.new(),
        oldest_message_id: nil,
        pending_messages: %{},
        online_users: [],
        typing_users: [],
        input_text: ""
      })
      |> Phoenix.LiveView.stream(:messages, [])

    %{outsider: outsider, room: room, socket: socket}
  end

  test "forged room selection does not expose messages", %{room: room, socket: socket} do
    assert {:noreply, updated_socket} =
             ChatLive.handle_event("select_room", %{"room_id" => room.id}, socket)

    assert updated_socket.assigns.current_room == nil
    assert MapSet.size(updated_socket.assigns.message_ids) == 0
  end

  test "forged message submission does not persist content", %{room: room, socket: socket} do
    socket = assign(socket, current_room: room)

    assert {:noreply, _updated_socket} =
             ChatLive.handle_event("send_message", %{"text" => "intrusão"}, socket)

    assert Messages.get_room_messages_count(room.id) == 0
  end
end
