defmodule ChatWeb.RoomSearchTest do
  use Chat.DataCase, async: true

  import Phoenix.Component, only: [assign: 2]

  alias Chat.Auth.Identity
  alias Chat.Rooms
  alias ChatWeb.ChatLive

  test "active search filters available rooms by name or description" do
    {:ok, user} = Identity.sync_user(%{"sub" => "room-search-user"}, %{})
    {:ok, owner} = Identity.sync_user(%{"sub" => "room-search-owner"}, %{})
    {:ok, finance} = Rooms.create_room(%{"name" => "Financeiro"}, owner.id)

    {:ok, support} =
      Rooms.create_room(%{"name" => "Atendimento", "description" => "Suporte técnico"}, owner.id)

    socket =
      %Phoenix.LiveView.Socket{}
      |> assign(%{current_user: user, available_rooms: [], room_search: ""})

    assert {:noreply, socket} =
             ChatLive.handle_event("search_rooms", %{"query" => "FINAN"}, socket)

    assert Enum.map(socket.assigns.available_rooms, & &1.id) == [finance.id]
    assert socket.assigns.room_search == "FINAN"

    assert {:noreply, socket} =
             ChatLive.handle_event("search_rooms", %{"query" => "técnico"}, socket)

    assert Enum.map(socket.assigns.available_rooms, & &1.id) == [support.id]

    assert {:noreply, unchanged_socket} =
             ChatLive.handle_event("search_rooms", %{"query" => %{}}, socket)

    assert unchanged_socket.assigns.room_search == socket.assigns.room_search

    assert {:noreply, socket} = ChatLive.handle_event("clear_room_search", %{}, socket)

    available_room_ids = MapSet.new(socket.assigns.available_rooms, & &1.id)
    assert MapSet.subset?(MapSet.new([finance.id, support.id]), available_room_ids)
    assert socket.assigns.room_search == ""
  end

  test "search ignores an overlong query without changing explorer state" do
    {:ok, user} = Identity.sync_user(%{"sub" => "room-search-limit-user"}, %{})
    {:ok, owner} = Identity.sync_user(%{"sub" => "room-search-limit-owner"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Operações"}, owner.id)

    socket =
      %Phoenix.LiveView.Socket{}
      |> assign(%{current_user: user, available_rooms: [room], room_search: "opera"})

    overlong_query = String.duplicate("x", 101)

    assert {:noreply, unchanged_socket} =
             ChatLive.handle_event("search_rooms", %{"query" => overlong_query}, socket)

    assert unchanged_socket.assigns.available_rooms == [room]
    assert unchanged_socket.assigns.room_search == "opera"
  end

  test "explorer follows the accessible Carbon active-search anatomy" do
    template =
      File.read!(
        Path.expand("../../../lib/chat_web/live/components/room_modal_component.ex", __DIR__)
      )

    assert template =~ ~s(role="search")
    assert template =~ ~s(aria-label="Buscar salas")
    assert template =~ ~s(id="room-search-input")
    assert template =~ ~s(aria-controls="room-explorer-results")
    assert template =~ ~s(phx-change="search_rooms")
    assert template =~ ~s(phx-click="clear_room_search")
    assert template =~ ~s(aria-live="polite")
    assert template =~ ~s(id="room-explorer-results")
    assert template =~ ~s(maxlength="100")
  end
end
