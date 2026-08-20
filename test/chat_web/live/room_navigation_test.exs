defmodule ChatWeb.RoomNavigationTest do
  use Chat.DataCase, async: true

  import Phoenix.Component, only: [assign: 2]

  alias Chat.Auth.Identity
  alias Chat.Rooms
  alias ChatWeb.RoomNavigation

  test "refresh reloads assigned rooms and unread counts without resetting navigation state" do
    {:ok, user} = Identity.sync_user(%{"sub" => "room-navigation-refresh-user"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Operações"}, user.id)

    socket =
      %Phoenix.LiveView.Socket{}
      |> assign(%{
        current_user: user,
        rooms: [],
        unread_counts: %{Ecto.UUID.generate() => 1},
        room_dialog: :explore,
        room_search: "opera",
        available_rooms: []
      })

    refreshed_socket = RoomNavigation.refresh(socket)

    assert [refreshed_room] = refreshed_socket.assigns.rooms
    assert refreshed_room.id == room.id
    assert refreshed_socket.assigns.unread_counts == %{}
    assert refreshed_socket.assigns.room_dialog == :explore
    assert refreshed_socket.assigns.room_search == "opera"
  end
end
