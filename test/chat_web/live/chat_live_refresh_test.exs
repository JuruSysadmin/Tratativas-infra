defmodule ChatWeb.ChatLiveRefreshTest do
  use ChatWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Chat.Auth.Identity
  alias Chat.Messages
  alias Chat.Rooms

  test "refresh restores the selected room from the authenticated URL", %{conn: conn} do
    {:ok, user} = Identity.sync_user(%{"sub" => "refresh-member"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Sala persistente"}, user.id)
    {:ok, _message} = Messages.create_message(%{"content" => "Antes do F5"}, user.id, room.id)

    conn = init_test_session(conn, %{"user_id" => user.id})
    {:ok, view, _html} = live(conn, ~p"/chat")

    view
    |> element(
      ~s(button.room-list-button[phx-click="select_room"][phx-value-room_id="#{room.id}"])
    )
    |> render_click()

    assert_patch(view, ~p"/chat?room_id=#{room.id}")

    refreshed_conn =
      Phoenix.ConnTest.build_conn()
      |> init_test_session(%{"user_id" => user.id})

    assert {:ok, refreshed_view, _html} =
             live(refreshed_conn, ~p"/chat?room_id=#{room.id}")

    assert has_element?(refreshed_view, "#message-form")
    assert render(refreshed_view) =~ "Sala persistente"
    assert render(refreshed_view) =~ "Antes do F5"

    GenServer.stop(view.pid)
    GenServer.stop(refreshed_view.pid)
  end

  test "refresh cannot select a room belonging to another user", %{conn: conn} do
    {:ok, owner} = Identity.sync_user(%{"sub" => "refresh-owner"}, %{})
    {:ok, outsider} = Identity.sync_user(%{"sub" => "refresh-outsider"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Sala privada no refresh"}, owner.id)

    conn = init_test_session(conn, %{"user_id" => outsider.id})
    assert {:ok, view, _html} = live(conn, ~p"/chat?room_id=#{room.id}")

    refute has_element?(view, "#message-form")
    refute render(view) =~ "Sala privada no refresh"

    GenServer.stop(view.pid)
  end
end
