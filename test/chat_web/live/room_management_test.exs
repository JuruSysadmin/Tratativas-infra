defmodule ChatWeb.RoomManagementTest do
  use Chat.DataCase, async: true

  import Phoenix.Component, only: [assign: 2]

  alias Chat.Auth.Identity
  alias Chat.Rooms
  alias ChatWeb.ChatLive
  alias Phoenix.HTML.Safe

  setup do
    {:ok, user} = Identity.sync_user(%{"sub" => "room-manager"}, %{})

    socket =
      %Phoenix.LiveView.Socket{private: %{lifecycle: %Phoenix.LiveView.Lifecycle{}}}
      |> assign(%{
        current_user: user,
        rooms: [],
        current_room: nil,
        message_ids: MapSet.new(),
        oldest_message_id: nil,
        pending_messages: %{},
        online_users: [],
        typing_users: [],
        input_text: "",
        navigation_open: false,
        room_dialog: nil,
        available_rooms: []
      })
      |> Phoenix.LiveView.stream(:messages, [])

    %{user: user, socket: socket}
  end

  test "creates, joins and selects a room", %{user: user, socket: socket} do
    params = %{"room" => %{"name" => "Operações", "description" => "Equipe"}}
    assert {:noreply, socket} = ChatLive.handle_event("open_new_room", %{}, socket)

    assert {:noreply, socket} = ChatLive.handle_event("create_room", params, socket)
    assert socket.assigns.current_room.name == "Operações"
    assert Enum.any?(socket.assigns.rooms, &(&1.id == socket.assigns.current_room.id))
    assert Rooms.room_member?(user.id, socket.assigns.current_room.id)
    assert socket.assigns.room_dialog == nil
  end

  test "rejects a direct create event while the creation dialog is closed", %{
    user: user,
    socket: socket
  } do
    params = %{"room" => %{"name" => "Criação forjada"}}

    assert {:noreply, returned_socket} = ChatLive.handle_event("create_room", params, socket)

    assert returned_socket.assigns.room_dialog == nil
    assert Rooms.get_user_rooms(user.id) == []
  end

  test "explores and joins rooms that are not memberships", %{user: user, socket: socket} do
    {:ok, owner} = Identity.sync_user(%{"sub" => "another-owner"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Geral"}, owner.id)

    assert {:noreply, socket} = ChatLive.handle_event("open_room_explorer", %{}, socket)
    assert Enum.any?(socket.assigns.available_rooms, &(&1.id == room.id))

    assert {:noreply, socket} =
             ChatLive.handle_event("join_room", %{"room_id" => room.id}, socket)

    assert Rooms.room_member?(user.id, room.id)
    assert socket.assigns.current_room.id == room.id
    assert socket.assigns.room_dialog == nil
  end

  test "rejects a direct join event while the room explorer is closed", %{
    user: user,
    socket: socket
  } do
    {:ok, owner} = Identity.sync_user(%{"sub" => "direct-join-owner"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Entrada forjada"}, owner.id)

    assert {:noreply, returned_socket} =
             ChatLive.handle_event("join_room", %{"room_id" => room.id}, socket)

    assert returned_socket.assigns.room_dialog == nil
    refute Rooms.room_member?(user.id, room.id)
  end

  test "shows a specific error when joining a room that no longer exists", %{socket: socket} do
    socket = %{
      socket
      | assigns: Map.put(socket.assigns, :flash, %{}),
        private: Map.put(socket.private, :live_temp, %{})
    }

    assert {:noreply, socket} = ChatLive.handle_event("open_room_explorer", %{}, socket)

    assert {:noreply, socket} =
             ChatLive.handle_event("join_room", %{"room_id" => Ecto.UUID.generate()}, socket)

    assert socket.assigns.flash["error"] == "Sala não encontrada"
  end

  test "a non-creator leaves the selected room", %{user: user, socket: socket} do
    {:ok, owner} = Identity.sync_user(%{"sub" => "leave-owner"}, %{"username" => "leave-owner"})
    {:ok, room} = Rooms.create_room(%{"name" => "Temporária"}, owner.id)
    {:ok, _membership} = Rooms.join_room(user.id, room.id)
    socket = assign(socket, rooms: [room], current_room: room)

    assert {:noreply, socket} =
             ChatLive.handle_event("leave_room", %{"room_id" => room.id}, socket)

    refute Rooms.room_member?(user.id, room.id)
    assert socket.assigns.current_room == nil
    assert socket.assigns.rooms == []
  end

  test "room header leave button has accessible label", %{user: user} do
    {:ok, owner} = Identity.sync_user(%{"sub" => "a11y-owner"}, %{"username" => "a11y-owner"})
    {:ok, room} = Rooms.create_room(%{"name" => "Acessibilidade"}, owner.id)
    room = Chat.Repo.preload(room, [:creator, :members])
    {:ok, _membership} = Rooms.join_room(user.id, room.id)

    html =
      ChatWeb.ChatAreaComponent.chat_area(%{
        current_room: room,
        current_user: user,
        messages: [],
        has_more_messages: false,
        pending_messages: %{},
        pending_message_order: [],
        status_messages: [],
        typing_users: [],
        input_text: "",
        mention_suggestions: [],
        message_statuses: %{},
        rooms: [room]
      })
      |> Safe.to_iodata()
      |> to_string()

    assert html =~ ~s(aria-label=\"Sair da sala Acessibilidade\")
    assert html =~ ~s(title=\"Sair da sala\")
  end

  test "empty state renders without open button when rooms list is empty", %{user: user} do
    html =
      ChatWeb.ChatAreaComponent.chat_area(%{
        current_room: nil,
        current_user: user,
        messages: [],
        has_more_messages: false,
        pending_messages: %{},
        pending_message_order: [],
        status_messages: [],
        typing_users: [],
        input_text: "",
        mention_suggestions: [],
        message_statuses: %{},
        rooms: []
      })
      |> Safe.to_iodata()
      |> to_string()

    assert html =~ "Comece criando uma sala"
    refute html =~ "Abrir primeira sala"
  end

  test "empty state opens first room when rooms are present", %{user: user} do
    {:ok, owner} =
      Identity.sync_user(%{"sub" => "empty-state-owner"}, %{"username" => "empty-state-owner"})

    {:ok, room} = Rooms.create_room(%{"name" => "Primeira"}, owner.id)
    room = Chat.Repo.preload(room, [:creator, :members])
    {:ok, _membership} = Rooms.join_room(user.id, room.id)

    html =
      ChatWeb.ChatAreaComponent.chat_area(%{
        current_room: nil,
        current_user: user,
        messages: [],
        has_more_messages: false,
        pending_messages: %{},
        pending_message_order: [],
        status_messages: [],
        typing_users: [],
        input_text: "",
        mention_suggestions: [],
        message_statuses: %{},
        rooms: [room]
      })
      |> Safe.to_iodata()
      |> to_string()

    assert html =~ "Comece uma conversa"
    assert html =~ ~s(phx-value-room_id=\"#{room.id}\")
    assert html =~ "Abrir primeira sala"
  end

  test "typing indicator renders when users are typing", %{user: user} do
    {:ok, owner} = Identity.sync_user(%{"sub" => "typing-owner"}, %{"username" => "typing-owner"})
    {:ok, room} = Rooms.create_room(%{"name" => "Typing"}, owner.id)
    room = Chat.Repo.preload(room, [:creator, :members])
    {:ok, _membership} = Rooms.join_room(user.id, room.id)

    html =
      ChatWeb.ChatAreaComponent.chat_area(%{
        current_room: room,
        current_user: user,
        messages: [],
        has_more_messages: false,
        pending_messages: %{},
        pending_message_order: [],
        status_messages: [],
        typing_users: [%{username: "Maria"}],
        input_text: "",
        mention_suggestions: [],
        message_statuses: %{},
        rooms: [room]
      })
      |> Safe.to_iodata()
      |> to_string()

    assert html =~ "typing-indicator"
    assert html =~ "Maria"
    assert html =~ "está digitando..."
  end

  test "typing indicator is hidden when no users are typing", %{user: user} do
    {:ok, owner} =
      Identity.sync_user(%{"sub" => "typing-none-owner"}, %{"username" => "typing-none-owner"})

    {:ok, room} = Rooms.create_room(%{"name" => "Typing None"}, owner.id)
    room = Chat.Repo.preload(room, [:creator, :members])
    {:ok, _membership} = Rooms.join_room(user.id, room.id)

    html =
      ChatWeb.ChatAreaComponent.chat_area(%{
        current_room: room,
        current_user: user,
        messages: [],
        has_more_messages: false,
        pending_messages: %{},
        pending_message_order: [],
        status_messages: [],
        typing_users: [],
        input_text: "",
        mention_suggestions: [],
        message_statuses: %{},
        rooms: [room]
      })
      |> Safe.to_iodata()
      |> to_string()

    refute html =~ "typing-indicator"
  end

  test "the creator deletes a room after confirmation", %{user: user, socket: socket} do
    {:ok, room} = Rooms.create_room(%{"name" => "Descartável"}, user.id)
    socket = assign(socket, rooms: [room], current_room: room)

    assert {:noreply, socket} =
             ChatLive.handle_event("delete_room", %{"room_id" => room.id}, socket)

    assert Rooms.get_room(room.id) == nil
    assert socket.assigns.current_room == nil
    assert socket.assigns.rooms == []
  end
end
