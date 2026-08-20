defmodule ChatWeb.ChatLiveHistoryTest do
  use Chat.DataCase, async: false

  import Phoenix.Component, only: [assign: 2]

  alias Chat.Auth.Identity
  alias Chat.Messages
  alias Chat.Rooms
  alias ChatWeb.ChatLive

  setup do
    {:ok, owner} = Identity.sync_user(%{"sub" => "history-owner"}, %{})
    {:ok, other} = Identity.sync_user(%{"sub" => "history-other"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Histórico"}, owner.id)
    {:ok, _membership} = Rooms.join_room(other.id, room.id)

    socket =
      %Phoenix.LiveView.Socket{private: %{lifecycle: %Phoenix.LiveView.Lifecycle{}}}
      |> assign(%{
        current_user: owner,
        current_room: room,
        message_ids: MapSet.new(),
        message_map: %{},
        message_statuses: %{},
        oldest_message_id: nil,
        pending_messages: %{},
        has_more_messages: false,
        online_users: [],
        typing_users: [],
        input_text: ""
      })
      |> Phoenix.LiveView.stream(:messages, [])

    %{other: other, owner: owner, room: room, socket: socket}
  end

  test "lists the previous page before a message without overlap", %{owner: owner, room: room} do
    messages =
      for index <- 1..4 do
        {:ok, message} =
          Messages.create_message(%{"content" => "Mensagem #{index}"}, owner.id, room.id)

        message
      end

    latest = Messages.list_messages(room.id, limit: 2)
    previous = Messages.list_messages(room.id, limit: 2, before: hd(latest).id)

    ordered = Messages.list_messages(room.id, limit: length(messages))

    assert Enum.map(latest, & &1.id) == Enum.map(Enum.take(ordered, -2), & &1.id)
    assert Enum.map(previous, & &1.id) == Enum.map(Enum.take(ordered, 2), & &1.id)
  end

  test "loads older messages at the beginning and updates the end flag", %{
    owner: owner,
    room: room,
    socket: socket
  } do
    for index <- 1..3 do
      {:ok, _message} =
        Messages.create_message(%{"content" => "Antiga #{index}"}, owner.id, room.id)
    end

    latest = Messages.list_messages(room.id, limit: 2)
    older = Messages.list_messages(room.id, limit: 2, before: hd(latest).id)

    socket =
      socket
      |> Phoenix.LiveView.stream(:messages, latest)
      |> assign(
        message_ids: MapSet.new(latest, & &1.id),
        oldest_message_id: hd(latest).id,
        has_more_messages: true
      )

    assert {:noreply, socket} = ChatLive.handle_event("load_older_messages", %{}, socket)
    assert socket.assigns.message_ids == MapSet.new(older ++ latest, & &1.id)

    refute socket.assigns.has_more_messages
  end

  test "only the author can delete a message", %{
    other: other,
    owner: owner,
    room: room,
    socket: socket
  } do
    {:ok, message} = Messages.create_message(%{"content" => "Privada"}, owner.id, room.id)

    other_socket =
      assign(socket,
        current_user: other,
        message_ids: MapSet.new([message.id])
      )

    assert {:noreply, other_socket} =
             ChatLive.handle_event("delete_message", %{"message_id" => message.id}, other_socket)

    assert Messages.get_message(message.id)
    assert MapSet.member?(other_socket.assigns.message_ids, message.id)

    owner_socket = assign(socket, message_ids: MapSet.new([message.id]))

    assert {:noreply, owner_socket} =
             ChatLive.handle_event("delete_message", %{"message_id" => message.id}, owner_socket)

    assert Messages.get_message(message.id) == nil
    refute MapSet.member?(owner_socket.assigns.message_ids, message.id)
  end

  test "requires confirmation before deleting a message", %{
    owner: owner,
    room: room,
    socket: socket
  } do
    {:ok, message} = Messages.create_message(%{"content" => "Confirmar"}, owner.id, room.id)

    assert {:noreply, socket} =
             ChatLive.handle_event(
               "confirm_delete_message",
               %{"message_id" => message.id},
               socket
             )

    assert socket.assigns.pending_message_deletion_id == message.id
    assert Messages.get_message(message.id)

    assert {:noreply, socket} = ChatLive.handle_event("cancel_delete_message", %{}, socket)
    assert socket.assigns.pending_message_deletion_id == nil
    assert Messages.get_message(message.id)
  end

  test "ignores delayed deletion from another room", %{owner: owner, socket: socket} do
    {:ok, other_room} = Rooms.create_room(%{"name" => "Outra"}, owner.id)

    {:ok, message} =
      Messages.create_message(%{"content" => "Outra sala"}, owner.id, other_room.id)

    socket = assign(socket, message_ids: MapSet.new([message.id]))

    assert {:noreply, socket} =
             ChatLive.handle_info({:message_deleted, other_room.id, message.id}, socket)

    assert MapSet.member?(socket.assigns.message_ids, message.id)
  end
end
