defmodule ChatWeb.MentionRealtimeTest do
  use ChatWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Chat.Auth.Identity
  alias Chat.Messages
  alias Chat.Rooms

  test "updates and clears the personal mention badge without reload", %{conn: conn} do
    {:ok, author} = Identity.sync_user(%{"sub" => "mention-realtime-author"}, %{})
    {:ok, mentioned} = Identity.sync_user(%{"sub" => "mention-realtime-target"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Menções realtime"}, author.id)
    assert {:ok, _membership} = Rooms.join_room(mentioned.id, room.id)

    conn = init_test_session(conn, %{"user_id" => mentioned.id})
    {:ok, view, _html} = live(conn, ~p"/chat")
    refute has_element?(view, "#mention-unread-count")

    assert {:ok, _message} =
             Messages.create_message(
               %{"content" => "Atenção @#{mentioned.username}"},
               author.id,
               room.id
             )

    _ = :sys.get_state(view.pid)
    assert has_element?(view, "#mention-unread-count", "1")

    view
    |> element(~s(#room-select-#{room.id}))
    |> render_click()

    refute has_element?(view, "#mention-unread-count")

    assert {:ok, second_message} =
             Messages.create_message(
               %{"content" => "Nova menção @#{mentioned.username}"},
               author.id,
               room.id
             )

    _ = :sys.get_state(view.pid)
    assert has_element?(view, "#mention-unread-count", "1")

    render_hook(view, "mark_read", %{"message_ids" => [second_message.id]})

    refute has_element?(view, "#mention-unread-count")
  end

  test "selecting a room clears the badge in another session of the same user", %{conn: conn} do
    {:ok, author} = Identity.sync_user(%{"sub" => "mention-session-author"}, %{})
    {:ok, mentioned} = Identity.sync_user(%{"sub" => "mention-session-target"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Menções entre sessões"}, author.id)
    assert {:ok, _membership} = Rooms.join_room(mentioned.id, room.id)

    assert {:ok, _message} =
             Messages.create_message(
               %{"content" => "Atenção @#{mentioned.username}"},
               author.id,
               room.id
             )

    conn = init_test_session(conn, %{"user_id" => mentioned.id})
    {:ok, reading_view, _html} = live(conn, ~p"/chat")
    {:ok, other_view, _html} = live(conn, ~p"/chat")

    assert has_element?(reading_view, "#mention-unread-count", "1")
    assert has_element?(other_view, "#mention-unread-count", "1")

    reading_view
    |> element(~s(#room-select-#{room.id}))
    |> render_click()

    _ = :sys.get_state(other_view.pid)
    refute has_element?(other_view, "#mention-unread-count")
  end

  test "leaving an unselected room removes its mentions from the badge", %{conn: conn} do
    {:ok, author} = Identity.sync_user(%{"sub" => "mention-leave-author"}, %{})
    {:ok, mentioned} = Identity.sync_user(%{"sub" => "mention-leave-target"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Menções ao sair"}, author.id)
    assert {:ok, _membership} = Rooms.join_room(mentioned.id, room.id)

    conn = init_test_session(conn, %{"user_id" => mentioned.id})
    {:ok, view, _html} = live(conn, ~p"/chat")

    assert {:ok, _message} =
             Messages.create_message(
               %{"content" => "Atenção @#{mentioned.username}"},
               author.id,
               room.id
             )

    _ = :sys.get_state(view.pid)
    assert has_element?(view, "#mention-unread-count", "1")

    render_click(view, "leave_room", %{"room_id" => room.id})

    refute has_element?(view, "#mention-unread-count")
  end

  test "leaving through the domain updates every connected session", %{conn: conn} do
    {:ok, author} = Identity.sync_user(%{"sub" => "mention-domain-leave-author"}, %{})
    {:ok, mentioned} = Identity.sync_user(%{"sub" => "mention-domain-leave-target"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Saída entre sessões"}, author.id)
    assert {:ok, _membership} = Rooms.join_room(mentioned.id, room.id)

    assert {:ok, _message} =
             Messages.create_message(
               %{"content" => "Atenção @#{mentioned.username}"},
               author.id,
               room.id
             )

    conn = init_test_session(conn, %{"user_id" => mentioned.id})
    {:ok, first_view, _html} = live(conn, ~p"/chat")
    {:ok, second_view, _html} = live(conn, ~p"/chat")
    assert has_element?(first_view, "#mention-unread-count", "1")
    assert has_element?(second_view, "#mention-unread-count", "1")

    assert {:ok, 1} = Rooms.leave_room(mentioned.id, room.id)

    _ = :sys.get_state(first_view.pid)
    _ = :sys.get_state(second_view.pid)
    refute has_element?(first_view, "#mention-unread-count")
    refute has_element?(second_view, "#mention-unread-count")
    refute has_element?(first_view, ~s(#room-select-#{room.id}))
    refute has_element?(second_view, ~s(#room-select-#{room.id}))
  end

  test "deleting a room clears its mentions for another connected member", %{conn: conn} do
    {:ok, owner} = Identity.sync_user(%{"sub" => "mention-delete-room-owner"}, %{})
    {:ok, mentioned} = Identity.sync_user(%{"sub" => "mention-delete-room-target"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Menções ao excluir"}, owner.id)
    assert {:ok, _membership} = Rooms.join_room(mentioned.id, room.id)

    conn = init_test_session(conn, %{"user_id" => mentioned.id})
    {:ok, view, _html} = live(conn, ~p"/chat")

    assert {:ok, _message} =
             Messages.create_message(
               %{"content" => "Atenção @#{mentioned.username}"},
               owner.id,
               room.id
             )

    _ = :sys.get_state(view.pid)
    assert has_element?(view, "#mention-unread-count", "1")
    assert has_element?(view, ~s(#room-select-#{room.id}))

    assert {:ok, _deleted_room} = Rooms.delete_room(room)

    _ = :sys.get_state(view.pid)
    refute has_element?(view, "#mention-unread-count")
    refute has_element?(view, ~s(#room-select-#{room.id}))
  end
end
