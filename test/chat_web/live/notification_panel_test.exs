defmodule ChatWeb.NotificationPanelTest do
  use ChatWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Chat.Auth.Identity
  alias Chat.Messages
  alias Chat.Repo
  alias Chat.Rooms
  alias Chat.Rooms.RoomMember

  test "opens persisted mention notifications and navigates to the mentioned message room", %{
    conn: conn
  } do
    {:ok, author} = Identity.sync_user(%{"sub" => "notification-panel-author"}, %{})
    {:ok, notified} = Identity.sync_user(%{"sub" => "notification-panel-target"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Alertas da equipe"}, author.id)
    assert {:ok, _membership} = Rooms.join_room(notified.id, room.id)

    assert {:ok, message} =
             Messages.create_message(
               %{"content" => "Atenção @#{notified.username}"},
               author.id,
               room.id
             )

    conn = init_test_session(conn, %{"user_id" => notified.id})
    {:ok, view, _html} = live(conn, ~p"/chat")

    assert has_element?(view, "#notification-toggle[aria-expanded=false]")
    assert has_element?(view, "#notification-toggle[aria-label='Notificações, 1 não lida']")
    assert has_element?(view, "#notification-badge", "1")
    refute has_element?(view, "#notification-panel")

    view |> element("#notification-toggle") |> render_click()

    assert has_element?(view, "#notification-toggle[aria-expanded=true]")
    assert has_element?(view, "#notification-panel[role=region]")
    assert has_element?(view, "#notification-#{message.id}", author.username)
    assert has_element?(view, "#notification-#{message.id}", room.name)

    view |> element("#notification-#{message.id}") |> render_click()

    assert has_element?(view, "#chat-room-title", room.name)
    refute has_element?(view, "#notification-panel")
    refute has_element?(view, "#notification-badge")
    assert has_element?(view, "#notification-toggle[aria-label='Notificações, nenhuma não lida']")
  end

  test "loads the mentioned message when it is older than the latest page", %{conn: conn} do
    {:ok, author} = Identity.sync_user(%{"sub" => "notification-old-author"}, %{})
    {:ok, notified} = Identity.sync_user(%{"sub" => "notification-old-target"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Histórico longo"}, author.id)
    assert {:ok, _membership} = Rooms.join_room(notified.id, room.id)

    assert {:ok, mentioned_message} =
             Messages.create_message(
               %{"content" => "@#{notified.username}, mensagem antiga importante"},
               author.id,
               room.id
             )

    for index <- 1..55 do
      assert {:ok, _message} =
               Messages.create_message(
                 %{"content" => "Mensagem posterior #{index}"},
                 author.id,
                 room.id
               )
    end

    conn = init_test_session(conn, %{"user_id" => notified.id})
    {:ok, view, _html} = live(conn, ~p"/chat")
    view |> element("#notification-toggle") |> render_click()
    view |> element("#notification-#{mentioned_message.id}") |> render_click()

    assert has_element?(view, "#messages-#{mentioned_message.id}", "mensagem antiga importante")
    assert has_element?(view, "#sidebar-room-#{room.id} .room-unread-count", "55")

    render_hook(view, "mark_read", %{"message_ids" => [mentioned_message.id]})

    assert has_element?(view, "#sidebar-room-#{room.id} .room-unread-count", "55")
  end

  test "shows a realtime toast for a mention outside the selected room", %{conn: conn} do
    {:ok, author} = Identity.sync_user(%{"sub" => "notification-toast-author"}, %{})
    {:ok, notified} = Identity.sync_user(%{"sub" => "notification-toast-target"}, %{})
    {:ok, selected_room} = Rooms.create_room(%{"name" => "Sala atual"}, notified.id)
    {:ok, other_room} = Rooms.create_room(%{"name" => "Incidentes"}, author.id)
    assert {:ok, _membership} = Rooms.join_room(notified.id, other_room.id)

    conn = init_test_session(conn, %{"user_id" => notified.id})
    {:ok, view, _html} = live(conn, ~p"/chat?room_id=#{selected_room.id}")

    assert {:ok, _message} =
             Messages.create_message(
               %{"content" => "@#{notified.username}, revise o incidente"},
               author.id,
               other_room.id
             )

    assert has_element?(view, "#mention-notification-toast[role=status]", author.username)
    assert has_element?(view, "#mention-notification-toast", other_room.name)
    assert has_element?(view, "#notification-badge", "1")

    view |> element("#dismiss-mention-notification") |> render_click()
    refute has_element?(view, "#mention-notification-toast")
  end

  test "does not show a toast for a mention in the selected room", %{conn: conn} do
    {:ok, author} = Identity.sync_user(%{"sub" => "selected-room-toast-author"}, %{})
    {:ok, notified} = Identity.sync_user(%{"sub" => "selected-room-toast-target"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Sala acompanhada"}, author.id)
    assert {:ok, _membership} = Rooms.join_room(notified.id, room.id)

    conn = init_test_session(conn, %{"user_id" => notified.id})
    {:ok, view, _html} = live(conn, ~p"/chat?room_id=#{room.id}")

    assert {:ok, _message} =
             Messages.create_message(
               %{"content" => "@#{notified.username}, mensagem visível"},
               author.id,
               room.id
             )

    refute has_element?(view, "#mention-notification-toast")
  end

  test "ignores forged and malformed notification payloads", %{conn: conn} do
    {:ok, user} = Identity.sync_user(%{"sub" => "notification-forged-payload"}, %{})
    conn = init_test_session(conn, %{"user_id" => user.id})
    {:ok, view, _html} = live(conn, ~p"/chat")

    render_click(view, "open_notification", %{"message_id" => Ecto.UUID.generate()})
    render_click(view, "open_notification", %{"message_id" => %{"forged" => true}})
    render_click(view, "open_notification", %{})

    assert has_element?(view, "#notification-toggle[aria-expanded=false]")
    refute has_element?(view, "#chat-room-title")
  end

  test "rechecks membership when opening a notification from stale assigns", %{conn: conn} do
    {:ok, author} = Identity.sync_user(%{"sub" => "notification-stale-author"}, %{})
    {:ok, notified} = Identity.sync_user(%{"sub" => "notification-stale-target"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Sala revogada"}, author.id)
    assert {:ok, _membership} = Rooms.join_room(notified.id, room.id)

    assert {:ok, message} =
             Messages.create_message(
               %{"content" => "@#{notified.username}, acesso temporário"},
               author.id,
               room.id
             )

    conn = init_test_session(conn, %{"user_id" => notified.id})
    {:ok, view, _html} = live(conn, ~p"/chat")
    view |> element("#notification-toggle") |> render_click()
    assert has_element?(view, "#notification-#{message.id}")

    membership = Repo.get_by!(RoomMember, user_id: notified.id, room_id: room.id)
    Repo.delete!(membership)

    view |> element("#notification-#{message.id}") |> render_click()

    refute has_element?(view, "#chat-room-title", room.name)
    refute has_element?(view, "#messages-#{message.id}")
    refute has_element?(view, "#notification-panel")
  end

  test "rejects selecting a room from stale sidebar assigns", %{conn: conn} do
    {:ok, owner} = Identity.sync_user(%{"sub" => "stale-sidebar-owner"}, %{})
    {:ok, former_member} = Identity.sync_user(%{"sub" => "stale-sidebar-member"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Sala stale"}, owner.id)
    assert {:ok, _membership} = Rooms.join_room(former_member.id, room.id)

    conn = init_test_session(conn, %{"user_id" => former_member.id})
    {:ok, view, _html} = live(conn, ~p"/chat")
    assert has_element?(view, "#room-select-#{room.id}")

    membership = Repo.get_by!(RoomMember, user_id: former_member.id, room_id: room.id)
    Repo.delete!(membership)

    view
    |> element("#room-select-#{room.id}")
    |> render_click()

    refute has_element?(view, "#chat-room-title", room.name)
  end

  test "removes a visible toast when the user leaves its room", %{conn: conn} do
    {:ok, author} = Identity.sync_user(%{"sub" => "notification-toast-leave-author"}, %{})
    {:ok, notified} = Identity.sync_user(%{"sub" => "notification-toast-leave-target"}, %{})
    {:ok, selected_room} = Rooms.create_room(%{"name" => "Sala própria"}, notified.id)
    {:ok, mentioned_room} = Rooms.create_room(%{"name" => "Sala removida"}, author.id)
    assert {:ok, _membership} = Rooms.join_room(notified.id, mentioned_room.id)

    conn = init_test_session(conn, %{"user_id" => notified.id})
    {:ok, view, _html} = live(conn, ~p"/chat?room_id=#{selected_room.id}")

    assert {:ok, _message} =
             Messages.create_message(
               %{"content" => "@#{notified.username}, aviso temporário"},
               author.id,
               mentioned_room.id
             )

    assert has_element?(view, "#mention-notification-toast", mentioned_room.name)
    assert {:ok, 1} = Rooms.leave_room(notified.id, mentioned_room.id)

    refute has_element?(view, "#mention-notification-toast")
  end
end
