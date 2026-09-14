defmodule ChatWeb.MentionNotificationControllerTest do
  use ChatWeb.ConnCase, async: false

  alias Chat.Auth.Identity
  alias Chat.Messages
  alias Chat.Rooms
  alias ChatWeb.MentionNotificationController

  test "marks a mention as read for the authenticated user", %{conn: conn} do
    {:ok, author} = Identity.sync_user(%{"sub" => "notification-author"}, %{})
    {:ok, mentioned} = Identity.sync_user(%{"sub" => "notification-target"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Notificações"}, author.id)
    {:ok, _membership} = Rooms.join_room(mentioned.id, room.id)

    {:ok, message} =
      Messages.create_message(%{"content" => "Olá @#{mentioned.username}"}, author.id, room.id)

    assert Messages.count_unread_mentions(mentioned.id) == 1

    conn =
      conn
      |> assign(:current_user, mentioned)
      |> MentionNotificationController.mark_read(%{
        "message_id" => message.id,
        "room_id" => room.id
      })

    assert json_response(conn, 200) == %{"unread_count" => 0}
    assert Messages.count_unread_mentions(mentioned.id) == 0
  end
end
