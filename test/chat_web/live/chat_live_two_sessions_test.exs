defmodule ChatWeb.ChatLiveTwoSessionsTest do
  use ChatWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Chat.Auth.Identity
  alias Chat.Rooms

  test "two authenticated sessions interact in the same room", %{conn: conn} do
    {:ok, alice} = Identity.sync_user(%{"sub" => "alice-two-sessions"}, %{})
    {:ok, bruno} = Identity.sync_user(%{"sub" => "bruno-two-sessions"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Sala simultânea"}, alice.id)
    {:ok, _membership} = Rooms.join_room(bruno.id, room.id)
    {:ok, other_room} = Rooms.create_room(%{"name" => "Segunda sala"}, alice.id)
    {:ok, _membership} = Rooms.join_room(bruno.id, other_room.id)

    alice_conn = init_test_session(conn, %{"user_id" => alice.id})
    bruno_conn = init_test_session(recycle(conn), %{"user_id" => bruno.id})

    {:ok, alice_view, _html} = live(alice_conn, ~p"/chat")
    {:ok, bruno_view, _html} = live(bruno_conn, ~p"/chat")

    select_room(alice_view, room.id)
    select_room(bruno_view, room.id)

    assert has_element?(alice_view, "#message-form")
    assert has_element?(alice_view, ".room-header", "2 membros")
    refute has_element?(alice_view, ".room-header .online-badge")

    assert eventually(fn ->
             render(alice_view) =~ "bruno-two-sessions" and
               render(bruno_view) =~ "alice-two-sessions"
           end)

    alice_view
    |> form("#message-form", %{"text" => "Mensagem simultânea"})
    |> render_submit()

    assert eventually(fn -> render(alice_view) =~ "Mensagem simultânea" end)
    assert eventually(fn -> render(bruno_view) =~ "Mensagem simultânea" end)

    alice_view
    |> form("#message-form", %{"text" => "digitando"})
    |> render_change()

    assert eventually(fn ->
             has_element?(
               bruno_view,
               ".typing-indicator",
               "alice-two-sessions está digitando..."
             )
           end)

    alice_view
    |> element(~s(button[phx-click="confirm_delete_message"]))
    |> render_click()

    assert has_element?(alice_view, ~s([role="dialog"]), "Excluir mensagem")

    alice_view
    |> element(~s(button[phx-click="delete_message"]))
    |> render_click()

    assert eventually(fn -> not (render(bruno_view) =~ "Mensagem simultânea") end)

    select_room(bruno_view, other_room.id)

    assert eventually(fn ->
             not has_element?(alice_view, ".presence-list li", "bruno-two-sessions")
           end)

    refute render(alice_view) =~ "bruno-two-sessions saiu da sala"

    alice_view
    |> form("#message-form", %{"text" => "Somente na primeira sala"})
    |> render_submit()

    refute render(bruno_view) =~ "Somente na primeira sala"

    GenServer.stop(alice_view.pid)
    GenServer.stop(bruno_view.pid)
  end

  defp select_room(view, room_id) do
    view
    |> element(
      ~s(button.room-list-button[phx-click="select_room"][phx-value-room_id="#{room_id}"])
    )
    |> render_click()
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
