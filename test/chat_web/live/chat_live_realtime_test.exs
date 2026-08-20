defmodule ChatWeb.ChatLiveRealtimeTest do
  use Chat.DataCase, async: false

  import Phoenix.Component, only: [assign: 2]

  alias Chat.Auth.Identity
  alias Chat.Messages
  alias Chat.Rooms
  alias ChatWeb.ChatLive
  alias ChatWeb.Presence
  alias Phoenix.LiveView.Utils

  setup do
    {:ok, user} = Identity.sync_user(%{"sub" => "realtime-user"}, %{})
    {:ok, other} = Identity.sync_user(%{"sub" => "realtime-other"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Tempo real"}, user.id)
    {:ok, _membership} = Rooms.join_room(other.id, room.id)

    socket =
      %Phoenix.LiveView.Socket{
        private: %{lifecycle: %Phoenix.LiveView.Lifecycle{}, live_temp: %{}}
      }
      |> assign(%{
        current_user: user,
        current_room: room,
        message_ids: MapSet.new(),
        message_map: %{},
        message_statuses: %{},
        oldest_message_id: nil,
        pending_messages: %{},
        online_users: [],
        typing_users: [],
        input_text: ""
      })
      |> Phoenix.LiveView.stream(:messages, [])

    %{other: other, room: room, socket: socket, user: user}
  end

  test "message context publishes creations and deletions", %{room: room, user: user} do
    Phoenix.PubSub.subscribe(Chat.PubSub, "room:#{room.id}")

    assert {:ok, message} =
             Messages.create_message(%{"content" => "Olá"}, user.id, room.id)

    assert_receive {:message_created, published}
    assert published.id == message.id
    assert published.user.id == user.id

    assert {:ok, _message} = Messages.delete_message(message)
    assert_receive {:message_deleted, room_id, message_id}
    assert room_id == room.id
    assert message_id == message.id
  end

  test "new messages are appended once and only in the selected room", %{
    room: room,
    socket: socket,
    user: user
  } do
    assert {:ok, message} =
             Messages.create_message(%{"content" => "Sem duplicar"}, user.id, room.id)

    assert {:noreply, socket} = ChatLive.handle_info({:message_created, message}, socket)
    assert {:noreply, socket} = ChatLive.handle_info({:message_created, message}, socket)
    assert socket.assigns.message_ids == MapSet.new([message.id])

    refute ["play_notification_sound", %{room_id: room.id}] in Utils.get_push_events(socket)
  end

  test "notifies the browser when another member sends a message", %{
    other: other,
    room: room,
    socket: socket
  } do
    assert {:ok, message} =
             Messages.create_message(%{"content" => "Nova mensagem"}, other.id, room.id)

    assert {:noreply, socket} = ChatLive.handle_info({:message_created, message}, socket)

    assert ["play_notification_sound", %{room_id: room.id}] in Utils.get_push_events(socket)
  end

  test "does not append realtime content after membership is revoked", %{
    room: room,
    user: user,
    other: other,
    socket: socket
  } do
    membership = Chat.Repo.get_by!(Chat.Rooms.RoomMember, user_id: user.id, room_id: room.id)
    Chat.Repo.delete!(membership)

    assert {:ok, message} =
             Messages.create_message(%{"content" => "Conteúdo revogado"}, other.id, room.id)

    assert {:noreply, returned_socket} =
             ChatLive.handle_info({:message_created, message}, socket)

    refute MapSet.member?(returned_socket.assigns.message_ids, message.id)
    assert returned_socket.assigns.current_room == nil
  end

  test "presence diff refreshes other online users", %{
    other: other,
    room: room,
    socket: socket,
    user: user
  } do
    topic = "room:#{room.id}"

    {:ok, _ref} =
      Presence.track(self(), topic, to_string(other.id), %{
        id: other.id,
        username: other.username
      })

    on_exit(fn -> Presence.untrack(self(), topic, to_string(other.id)) end)

    broadcast = %Phoenix.Socket.Broadcast{topic: topic, event: "presence_diff", payload: %{}}
    assert {:noreply, socket} = ChatLive.handle_info(broadcast, socket)

    assert Enum.map(socket.assigns.online_users, & &1.id) == [other.id]
    refute Enum.any?(socket.assigns.online_users, &(&1.id == user.id))
  end

  test "update_input updates typing metadata via Presence", %{
    room: room,
    socket: socket
  } do
    topic = "room:#{room.id}"

    assert {:noreply, _socket} =
             ChatLive.handle_event("update_input", %{"text" => "digitando"}, socket)

    assert [meta] = Presence.list_online_users(topic)
    assert meta.id == socket.assigns.current_user.id
    assert meta.typing == true
  end

  test "presence diff refreshes typing users", %{
    other: other,
    room: room,
    socket: socket
  } do
    topic = "room:#{room.id}"

    {:ok, _ref} = Presence.track_user(self(), topic, other)
    {:ok, _} = Presence.update_typing(self(), topic, other, true)

    on_exit(fn -> Presence.untrack(self(), topic, Presence.presence_key(other.id)) end)

    Process.sleep(100)

    broadcast = %Phoenix.Socket.Broadcast{topic: topic, event: "presence_diff", payload: %{}}
    assert {:noreply, socket} = ChatLive.handle_info(broadcast, socket)

    assert Enum.map(socket.assigns.typing_users, & &1.id) == [other.id]
  end

  test "send_message clears typing metadata", %{
    room: room,
    socket: socket
  } do
    topic = "room:#{room.id}"

    {:noreply, typing_socket} =
      ChatLive.handle_event("update_input", %{"text" => "olá"}, socket)

    assert [typing_meta] = Presence.list_online_users(topic)
    assert typing_meta.typing == true

    {:noreply, _sent_socket} =
      ChatLive.handle_event("send_message", %{"text" => "olá"}, typing_socket)

    assert [meta] = Presence.list_online_users(topic)
    assert meta.typing == false
  end
end
