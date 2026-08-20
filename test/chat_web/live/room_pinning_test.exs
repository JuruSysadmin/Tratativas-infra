defmodule ChatWeb.RoomPinningTest do
  use ChatWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Chat.Auth.Identity
  alias Chat.Repo
  alias Chat.Rooms
  alias Chat.Rooms.RoomMember

  test "a member pins a conversation from the sidebar", %{conn: conn} do
    {:ok, user} = Identity.sync_user(%{"sub" => "sidebar-pin-member"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Produto"}, user.id)

    conn = init_test_session(conn, %{"user_id" => user.id})
    {:ok, view, _html} = live(conn, ~p"/chat")

    view
    |> element(~s(button[phx-click="pin_room"][phx-value-room_id="#{room.id}"]))
    |> render_click()

    assert has_element?(view, ~s(#pinned-rooms [data-room-id="#{room.id}"]))

    membership = Repo.get_by!(RoomMember, user_id: user.id, room_id: room.id)
    assert %DateTime{} = membership.pinned_at
  end

  test "a member unpins a conversation from the sidebar", %{conn: conn} do
    {:ok, user} = Identity.sync_user(%{"sub" => "sidebar-unpin-member"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Operações"}, user.id)
    assert {:ok, _membership} = Rooms.pin_room(user.id, room.id)

    conn = init_test_session(conn, %{"user_id" => user.id})
    {:ok, view, _html} = live(conn, ~p"/chat")

    view
    |> element(~s(button[phx-click="unpin_room"][phx-value-room_id="#{room.id}"]))
    |> render_click()

    assert has_element?(view, ~s(#conversation-rooms [data-room-id="#{room.id}"]))

    membership = Repo.get_by!(RoomMember, user_id: user.id, room_id: room.id)
    assert is_nil(membership.pinned_at)
  end

  test "a forged pin event cannot pin another user's room", %{conn: conn} do
    {:ok, owner} = Identity.sync_user(%{"sub" => "sidebar-pin-owner"}, %{})
    {:ok, outsider} = Identity.sync_user(%{"sub" => "sidebar-pin-outsider"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Restrita"}, owner.id)

    conn = init_test_session(conn, %{"user_id" => outsider.id})
    {:ok, view, _html} = live(conn, ~p"/chat")

    render_click(view, "pin_room", %{"room_id" => room.id})

    owner_membership = Repo.get_by!(RoomMember, user_id: owner.id, room_id: room.id)
    assert is_nil(owner_membership.pinned_at)
    refute has_element?(view, ~s([data-room-id="#{room.id}"]))
  end

  test "an invalid room id does not terminate the LiveView", %{conn: conn} do
    {:ok, user} = Identity.sync_user(%{"sub" => "sidebar-invalid-pin-member"}, %{})

    conn = init_test_session(conn, %{"user_id" => user.id})
    {:ok, view, _html} = live(conn, ~p"/chat")

    render_click(view, "pin_room", %{"room_id" => "not-a-uuid"})

    assert has_element?(view, "#room-navigation")
  end

  test "pin without a room id does not terminate the LiveView", %{conn: conn} do
    {:ok, user} = Identity.sync_user(%{"sub" => "sidebar-missing-pin-id"}, %{})

    conn = init_test_session(conn, %{"user_id" => user.id})
    {:ok, view, _html} = live(conn, ~p"/chat")

    render_click(view, "pin_room", %{})

    assert has_element?(view, "#room-navigation")
  end

  test "unpin without a room id does not terminate the LiveView", %{conn: conn} do
    {:ok, user} = Identity.sync_user(%{"sub" => "sidebar-missing-unpin-id"}, %{})

    conn = init_test_session(conn, %{"user_id" => user.id})
    {:ok, view, _html} = live(conn, ~p"/chat")

    render_click(view, "unpin_room", %{})

    assert has_element?(view, "#room-navigation")
  end

  test "unpin with an invalid room id does not terminate the LiveView", %{conn: conn} do
    {:ok, user} = Identity.sync_user(%{"sub" => "sidebar-invalid-unpin-member"}, %{})

    conn = init_test_session(conn, %{"user_id" => user.id})
    {:ok, view, _html} = live(conn, ~p"/chat")

    render_click(view, "unpin_room", %{"room_id" => "not-a-uuid"})

    assert has_element?(view, "#room-navigation")
  end
end
