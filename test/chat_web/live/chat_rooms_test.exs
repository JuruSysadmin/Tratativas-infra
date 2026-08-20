defmodule ChatWeb.ChatRoomsTest do
  use Chat.DataCase, async: true

  import Phoenix.Component, only: [assign: 2]

  alias Chat.Auth.Identity
  alias Chat.Messages
  alias Chat.Rooms
  alias ChatWeb.ChatRooms
  alias ChatWeb.PubSubManager

  setup do
    suffix = System.unique_integer([:positive])
    {:ok, user} = Identity.sync_user(%{"sub" => "chat-rooms-user-#{suffix}"}, %{})

    socket =
      %Phoenix.LiveView.Socket{private: %{lifecycle: %Phoenix.LiveView.Lifecycle{}}}
      |> assign(%{
        current_user: user,
        current_room: nil,
        rooms: [],
        unread_counts: %{},
        room_dialog: nil,
        available_rooms: [],
        room_search: "",
        navigation_open: false,
        message_ids: MapSet.new(),
        message_map: %{},
        message_order: [],
        message_statuses: %{},
        oldest_message_id: nil,
        pending_messages: %{},
        pending_message_order: [],
        has_more_messages: false,
        mention_notifications: [],
        mention_unread_count: 0,
        mention_suggestions: [],
        online_users: [],
        typing_users: [],
        pending_presence_leaves: %{},
        status_messages: [],
        input_text: ""
      })
      |> Phoenix.LiveView.stream(:messages, [])

    %{socket: socket, user: user}
  end

  test "create returns an updated socket with the new room selected", %{
    socket: socket,
    user: user
  } do
    socket = assign(socket, room_dialog: :new)

    assert {:ok, updated_socket} = ChatRooms.create(socket, %{"name" => "Direta"}, user.id)
    assert updated_socket.assigns.current_room.creator_id == user.id
    assert Ecto.assoc_loaded?(updated_socket.assigns.current_room.creator)
    assert Ecto.assoc_loaded?(updated_socket.assigns.current_room.members)
    assert updated_socket.assigns.room_dialog == nil
    assert [created_room] = updated_socket.assigns.rooms
    assert created_room.id == updated_socket.assigns.current_room.id
  end

  test "join returns an updated socket with the joined room selected", %{
    socket: socket,
    user: user
  } do
    suffix = System.unique_integer([:positive])
    {:ok, owner} = Identity.sync_user(%{"sub" => "chat-rooms-owner-#{suffix}"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Entrada direta"}, owner.id)

    socket = assign(socket, room_dialog: :explore, available_rooms: [room])

    assert {:ok, updated_socket} = ChatRooms.join(socket, room.id, user.id)
    assert updated_socket.assigns.current_room.id == room.id
    assert updated_socket.assigns.room_dialog == nil
    assert updated_socket.assigns.available_rooms == []
    assert updated_socket.assigns.room_search == ""
  end

  test "leave returns an updated socket without the departed room", %{socket: socket, user: user} do
    {:ok, owner} = Identity.sync_user(%{"sub" => "chat-rooms-leave-owner"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Saída"}, owner.id)
    {:ok, _membership} = Rooms.join_room(user.id, room.id)
    socket = assign(socket, rooms: [room], current_room: room)

    assert {:ok, updated_socket} = ChatRooms.leave(socket, room.id, user.id)
    assert updated_socket.assigns.rooms == []
    assert updated_socket.assigns.current_room == nil
  end

  test "delete returns an updated socket without the deleted room", %{socket: socket, user: user} do
    {:ok, room} = Rooms.create_room(%{"name" => "Exclusão"}, user.id)
    socket = assign(socket, rooms: [room], current_room: room, room_dialog: :delete)

    assert {:ok, updated_socket} = ChatRooms.delete(socket, room.id, user.id)
    assert updated_socket.assigns.rooms == []
    assert updated_socket.assigns.current_room == nil
    assert updated_socket.assigns.room_dialog == nil
  end

  test "room mutations return an error and the original socket on failure", %{
    socket: socket,
    user: user
  } do
    assert {:error, _changeset, ^socket} = ChatRooms.create(socket, %{"name" => ""}, user.id)
    assert {:error, :not_found, ^socket} = ChatRooms.join(socket, Ecto.UUID.generate(), user.id)
    assert {:error, :not_found, ^socket} = ChatRooms.leave(socket, Ecto.UUID.generate(), user.id)

    assert {:error, :not_authorized, ^socket} =
             ChatRooms.delete(socket, Ecto.UUID.generate(), user.id)
  end

  test "uses descriptive helpers for room navigation", %{socket: socket, user: user} do
    {:ok, room} = Rooms.create_room(%{"name" => "Navegação"}, user.id)
    socket = assign(socket, rooms: [room])

    assert %{assigns: %{room_dialog: :new}} = ChatRooms.open_new_room_dialog(socket)
    assert %{assigns: %{room_dialog: :explore}} = ChatRooms.open_room_explorer(socket)
    assert %{id: room_id} = ChatRooms.find_assigned_room(socket, room.id)
    assert room_id == room.id
  end

  test "subscribe does not join the PubSub topic of a room the user cannot access", %{
    socket: socket
  } do
    {:ok, owner} = Identity.sync_user(%{"sub" => "chat-rooms-subscribe-owner"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Restrita"}, owner.id)
    socket = %{socket | transport_pid: self()}

    ChatRooms.subscribe(socket, room)
    Phoenix.PubSub.broadcast(Chat.PubSub, "room:#{room.id}", {:private_room_event, room.id})

    refute_receive {:private_room_event, _room_id}
  end

  test "subscribe joins the PubSub topic of a room the user can access", %{
    socket: socket,
    user: user
  } do
    {:ok, room} = Rooms.create_room(%{"name" => "Autorizada"}, user.id)
    socket = %{socket | transport_pid: self()}

    ChatRooms.subscribe(socket, room)
    Phoenix.PubSub.broadcast(Chat.PubSub, "room:#{room.id}", {:authorized_room_event, room.id})

    room_id = room.id
    assert_receive {:authorized_room_event, ^room_id}
  end

  test "subscribe emits telemetry for an authorized room", %{socket: socket, user: user} do
    {:ok, room} = Rooms.create_room(%{"name" => "Telemetria"}, user.id)
    socket = %{socket | transport_pid: self()}
    handler_id = "room-subscription-telemetry-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:chat, :pubsub, :subscribe],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    PubSubManager.subscribe(socket, room)

    assert_receive {:telemetry, [:chat, :pubsub, :subscribe], %{},
                    %{room_id: room_id, user_id: user_id}}

    assert room_id == room.id
    assert user_id == user.id
  end

  test "subscribe_rooms uses the authorized room list without membership queries", %{
    socket: socket,
    user: user
  } do
    {:ok, first_room} = Rooms.create_room(%{"name" => "Batch one"}, user.id)
    {:ok, second_room} = Rooms.create_room(%{"name" => "Batch two"}, user.id)

    socket =
      socket
      |> assign(rooms: [first_room, second_room])
      |> then(&%{&1 | transport_pid: self()})

    test_pid = self()
    handler_id = "batch-subscription-query-counter-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:chat, :repo, :query],
        fn _event, _measurements, metadata, _config ->
          if self() == test_pid do
            send(test_pid, {:query, metadata.query})
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    PubSubManager.subscribe_rooms(socket)

    refute_receive {:query, _query}

    Phoenix.PubSub.broadcast(
      Chat.PubSub,
      "room:#{first_room.id}",
      {:batch_subscription, first_room.id}
    )

    Phoenix.PubSub.broadcast(
      Chat.PubSub,
      "room:#{second_room.id}",
      {:batch_subscription, second_room.id}
    )

    first_room_id = first_room.id
    second_room_id = second_room.id

    assert_receive {:batch_subscription, ^first_room_id}
    assert_receive {:batch_subscription, ^second_room_id}
  end

  test "subscribe_rooms emits aggregate telemetry", %{socket: socket, user: user} do
    {:ok, first_room} = Rooms.create_room(%{"name" => "Batch telemetry one"}, user.id)
    {:ok, second_room} = Rooms.create_room(%{"name" => "Batch telemetry two"}, user.id)

    socket =
      socket
      |> assign(rooms: [first_room, second_room])
      |> then(&%{&1 | transport_pid: self()})

    handler_id = "batch-subscription-telemetry-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:chat, :pubsub, :batch_subscribe],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    PubSubManager.subscribe_rooms(socket)

    assert_receive {:telemetry, [:chat, :pubsub, :batch_subscribe],
                    %{count: 2, duration: duration}, %{user_id: user_id}}

    assert duration >= 0
    assert user_id == user.id
  end

  test "refresh removes unread counts for rooms the user no longer belongs to", %{
    socket: socket,
    user: user
  } do
    {:ok, owner} = Identity.sync_user(%{"sub" => "chat-rooms-refresh-owner"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Badge removido"}, owner.id)
    {:ok, _membership} = Rooms.join_room(user.id, room.id)
    socket = assign(socket, rooms: [room], unread_counts: %{room.id => 3})

    assert {:ok, 1} = Rooms.leave_room(user.id, room.id)

    refreshed_socket = ChatRooms.refresh(socket)

    assert refreshed_socket.assigns.rooms == []
    assert refreshed_socket.assigns.unread_counts == %{}
  end

  test "increment_unread reloads the persisted count instead of incrementing a stale value", %{
    socket: socket,
    user: user
  } do
    {:ok, room} = Rooms.create_room(%{"name" => "Contador atualizado"}, user.id)
    {:ok, author} = Identity.sync_user(%{"sub" => "chat-rooms-author-increment"}, %{})
    {:ok, _membership} = Rooms.join_room(author.id, room.id)
    {:ok, _first} = Messages.create_message(%{"content" => "Primeira"}, author.id, room.id)
    {:ok, _second} = Messages.create_message(%{"content" => "Segunda"}, author.id, room.id)

    socket = assign(socket, %{rooms: [room], unread_counts: %{room.id => 0}})

    updated_socket = ChatRooms.increment_unread(socket, room.id)

    assert updated_socket.assigns.unread_counts == %{room.id => 2}
  end

  test "clear_unread reloads the persisted count instead of deleting a stale badge", %{
    socket: socket,
    user: user
  } do
    {:ok, room} = Rooms.create_room(%{"name" => "Limpeza atualizada"}, user.id)
    {:ok, author} = Identity.sync_user(%{"sub" => "chat-rooms-author-clear"}, %{})
    {:ok, _membership} = Rooms.join_room(author.id, room.id)

    {:ok, _message} =
      Messages.create_message(%{"content" => "Ainda não lida"}, author.id, room.id)

    socket = assign(socket, %{rooms: [room], unread_counts: %{room.id => 0}})

    updated_socket = ChatRooms.clear_unread(socket, room.id)

    assert updated_socket.assigns.unread_counts == %{room.id => 1}
  end
end
