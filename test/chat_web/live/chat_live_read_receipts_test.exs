defmodule ChatWeb.ChatLiveReadReceiptsTest do
  use ChatWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Chat.Auth.Identity
  alias Chat.Messages
  alias Chat.Rooms

  setup %{conn: conn} do
    {:ok, alice} = Identity.sync_user(%{"sub" => "alice-read"}, %{})
    {:ok, bruno} = Identity.sync_user(%{"sub" => "bruno-read"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Leituras"}, alice.id)
    {:ok, _membership} = Rooms.join_room(bruno.id, room.id)

    alice_conn = init_test_session(conn, %{"user_id" => alice.id})
    bruno_conn = init_test_session(recycle(conn), %{"user_id" => bruno.id})

    {:ok, alice_view, _html} = live(alice_conn, ~p"/chat?room_id=#{room.id}")
    {:ok, bruno_view, _html} = live(bruno_conn, ~p"/chat?room_id=#{room.id}")

    %{alice: alice, bruno: bruno, room: room, alice_view: alice_view, bruno_view: bruno_view}
  end

  test "sender sees 'Lida' after another user reads the message", %{
    alice_view: alice_view,
    bruno_view: bruno_view,
    room: room
  } do
    alice_view
    |> form("#message-form", %{"text" => "Olá Bruno"})
    |> render_submit()

    assert eventually(fn ->
             render(alice_view) =~ "Olá Bruno" && render(bruno_view) =~ "Olá Bruno"
           end)

    [message] = Messages.list_messages(room.id)

    render_hook(bruno_view, "mark_read", %{"message_ids" => [message.id]})

    assert eventually(fn ->
             html = render(alice_view)
             html =~ "✓✓" && html =~ "message-delivery-status--read"
           end)

    assert Messages.read_count(message.id, message.user_id) == 1
  end

  test "sender sees 'Lida' when another user opens the room after the message", %{
    alice_view: alice_view,
    bruno_view: bruno_view,
    room: room
  } do
    alice_view
    |> form("#message-form", %{"text" => "Lida ao abrir a sala"})
    |> render_submit()

    _ = :sys.get_state(alice_view.pid)
    _ = :sys.get_state(bruno_view.pid)
    assert render(bruno_view) =~ "Lida ao abrir a sala"

    bruno_view
    |> element(
      ~s(button.room-list-button[phx-click="select_room"][phx-value-room_id="#{room.id}"])
    )
    |> render_click()

    assert eventually(fn ->
             has_element?(alice_view, ".message-delivery-status--read", "✓✓")
           end)
  end

  test "does not mark the sender's own message and ignores duplicate reads", %{
    alice: alice,
    alice_view: alice_view,
    bruno_view: bruno_view,
    room: room
  } do
    Phoenix.PubSub.subscribe(Chat.PubSub, "room:#{room.id}")

    alice_view
    |> form("#message-form", %{"text" => "Uma leitura apenas"})
    |> render_submit()

    assert_receive {:message_created, message}, 1_000
    _ = :sys.get_state(bruno_view.pid)
    assert render(bruno_view) =~ "Uma leitura apenas"

    render_hook(alice_view, "mark_read", %{"message_ids" => [message.id]})
    assert Messages.list_readers(message.id) == []

    render_hook(bruno_view, "mark_read", %{"message_ids" => [message.id]})
    render_hook(bruno_view, "mark_read", %{"message_ids" => [message.id]})

    assert Messages.read_count(message.id, alice.id) == 1
  end

  test "does not mark a message from another room", %{
    alice: alice,
    bruno: bruno,
    bruno_view: bruno_view
  } do
    {:ok, other_room} = Rooms.create_room(%{"name" => "Outra sala de leitura"}, alice.id)
    {:ok, _membership} = Rooms.join_room(bruno.id, other_room.id)

    {:ok, message} =
      Messages.create_message(%{"content" => "Fora da sala atual"}, alice.id, other_room.id)

    render_hook(bruno_view, "mark_read", %{"message_ids" => [message.id]})

    assert Messages.list_readers(message.id) == []
  end

  test "sender sees two gray checks when another user receives but has not read", %{
    alice: _alice,
    alice_view: alice_view,
    bruno_view: bruno_view,
    room: room
  } do
    alice_view
    |> form("#message-form", %{"text" => "Não lida"})
    |> render_submit()

    [message] = Messages.list_messages(room.id)
    render_hook(bruno_view, "mark_delivered", %{"message_ids" => [message.id]})

    assert eventually(fn ->
             has_element?(
               alice_view,
               ".message-delivery-status--delivered",
               "✓✓"
             )
           end)

    refute render(alice_view) =~ "message-delivery-status--read"
  end

  test "sender sees delivered status after another browser acknowledges the message", %{
    alice: alice,
    alice_view: alice_view,
    bruno_view: bruno_view,
    room: room
  } do
    alice_view
    |> form("#message-form", %{"text" => "Confirmação de entrega"})
    |> render_submit()

    [message] = Messages.list_messages(room.id)
    assert Messages.delivery_count(message.id, alice.id) == 0
    refute has_element?(alice_view, ".message-delivery-status--delivered")

    render_hook(bruno_view, "mark_delivered", %{"message_ids" => [message.id]})

    assert eventually(fn ->
             Messages.delivery_count(message.id, alice.id) == 1 and
               has_element?(alice_view, ".message-delivery-status--delivered", "✓✓")
           end)
  end

  test "sender sees sent status when no one else is online", %{conn: conn} do
    {:ok, alone} = Identity.sync_user(%{"sub" => "alone-read"}, %{"username" => "alone-read"})
    {:ok, room} = Rooms.create_room(%{"name" => "Sozinha"}, alone.id)

    alone_conn = init_test_session(conn, %{"user_id" => alone.id})
    {:ok, alone_view, _html} = live(alone_conn, ~p"/chat?room_id=#{room.id}")

    alone_view
    |> form("#message-form", %{"text" => "Sozinha"})
    |> render_submit()

    assert eventually(fn ->
             html = render(alone_view)
             html =~ "Sozinha" && html =~ "✓" && html =~ "message-delivery-status"
           end)

    refute render(alone_view) =~ "message-delivery-status--delivered"
    refute render(alone_view) =~ "message-delivery-status--read"
  end

  test "read receipt updates status without changing message order", %{
    alice: alice,
    alice_view: alice_view,
    bruno_view: bruno_view,
    room: room
  } do
    messages =
      for index <- 1..3 do
        {:ok, message} =
          Messages.create_message(%{"content" => "Ordem leitura #{index}"}, alice.id, room.id)

        message
      end

    Enum.each([alice_view, bruno_view], fn view -> _ = :sys.get_state(view.pid) end)
    expected_ids = Enum.map(messages, & &1.id)
    assert rendered_message_ids(alice_view) == expected_ids

    render_hook(bruno_view, "mark_read", %{"message_ids" => [Enum.at(messages, 1).id]})
    _ = :sys.get_state(alice_view.pid)

    assert rendered_message_ids(alice_view) == expected_ids
  end

  defp rendered_message_ids(view) do
    Regex.scan(~r/id="messages-([0-9a-f-]{36})"/, render(view), capture: :all_but_first)
    |> List.flatten()
  end

  defp eventually(assertion, attempts \\ 20)

  defp eventually(assertion, attempts) when attempts > 0 do
    if assertion.() do
      true
    else
      eventually(assertion, attempts - 1)
    end
  end

  defp eventually(_assertion, 0), do: false
end
