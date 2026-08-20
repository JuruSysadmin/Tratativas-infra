defmodule ChatWeb.ChatLiveEditTest do
  use ChatWeb.ConnCase, async: false

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveViewTest

  alias Chat.Auth.Identity
  alias Chat.Messages
  alias Chat.Rooms
  alias ChatWeb.ChatLive

  describe "edit flow through a mounted LiveView" do
    setup %{conn: conn} do
      {:ok, author} = Identity.sync_user(%{"sub" => "edit-author"}, %{})
      {:ok, other} = Identity.sync_user(%{"sub" => "edit-other"}, %{})
      {:ok, room} = Rooms.create_room(%{"name" => "Sala de edição"}, author.id)
      {:ok, _membership} = Rooms.join_room(other.id, room.id)

      {:ok, message} =
        Messages.create_message(%{"content" => "Conteúdo original"}, author.id, room.id)

      author_conn = init_test_session(conn, %{"user_id" => author.id})
      other_conn = init_test_session(recycle(conn), %{"user_id" => other.id})

      %{
        author: author,
        other: other,
        room: room,
        message: message,
        author_conn: author_conn,
        other_conn: other_conn
      }
    end

    test "author edits a message and both sessions see the edited state", %{
      author_conn: author_conn,
      other_conn: other_conn,
      room: room,
      message: message
    } do
      {:ok, author_view, _html} = live(author_conn, ~p"/chat?room_id=#{room.id}")
      {:ok, other_view, _html} = live(other_conn, ~p"/chat?room_id=#{room.id}")

      assert render(author_view) =~ "Conteúdo original"

      author_view
      |> element(~s(.message-action-edit[phx-click="start_edit_message"]))
      |> render_click()

      assert has_element?(author_view, "#message-edit-dialog-title", "Editar mensagem")
      assert render(author_view) =~ "Conteúdo original"

      author_view
      |> form("#message-edit-form", %{"content" => "Conteúdo editado"})
      |> render_submit()

      assert eventually(fn -> render(author_view) =~ "Conteúdo editado" end)
      assert eventually(fn -> render(author_view) =~ ">editada<" end)
      refute has_element?(author_view, "#message-edit-dialog-title")

      assert eventually(fn -> render(other_view) =~ "Conteúdo editado" end)
      assert eventually(fn -> render(other_view) =~ ">editada<" end)

      assert Messages.get_message(message.id).content == "Conteúdo editado"
      assert Messages.get_message(message.id).edited_at != nil
      GenServer.stop(author_view.pid)
      GenServer.stop(other_view.pid)
    end

    test "author saves the current dialog content in one submit event", %{
      author_conn: author_conn,
      room: room,
      message: message
    } do
      {:ok, author_view, _html} = live(author_conn, ~p"/chat?room_id=#{room.id}")

      author_view
      |> element(~s(.message-action-edit[phx-click="start_edit_message"]))
      |> render_click()

      author_view
      |> form("#message-edit-form", %{"content" => "Conteúdo enviado ao salvar"})
      |> render_submit()

      assert Messages.get_message(message.id).content == "Conteúdo enviado ao salvar"
      assert Messages.get_message(message.id).edited_at != nil
      refute has_element?(author_view, "#message-edit-dialog-title")
      GenServer.stop(author_view.pid)
    end

    test "cancel closes the dialog without persisting", %{
      author_conn: author_conn,
      room: room,
      message: message
    } do
      {:ok, author_view, _html} = live(author_conn, ~p"/chat?room_id=#{room.id}")

      author_view
      |> element(~s(.message-action-edit[phx-click="start_edit_message"]))
      |> render_click()

      author_view
      |> element("#message-edit-cancel")
      |> render_click()

      refute has_element?(author_view, "#message-edit-dialog-title")
      assert Messages.get_message(message.id).content == "Conteúdo original"
      assert Messages.get_message(message.id).edited_at == nil
      GenServer.stop(author_view.pid)
    end

    test "another user has no edit action in the message menu", %{
      other_conn: other_conn,
      room: room
    } do
      {:ok, other_view, _html} = live(other_conn, ~p"/chat?room_id=#{room.id}")

      refute has_element?(
               other_view,
               ~s(.message-action-edit[phx-click="start_edit_message"])
             )

      assert render(other_view) =~ "Conteúdo original"
      GenServer.stop(other_view.pid)
    end
  end

  describe "server-side edit authorization on the socket" do
    setup do
      {:ok, author} = Identity.sync_user(%{"sub" => "edit-socket-author"}, %{})
      {:ok, other} = Identity.sync_user(%{"sub" => "edit-socket-other"}, %{})
      {:ok, room} = Rooms.create_room(%{"name" => "Sala protegida"}, author.id)
      {:ok, _membership} = Rooms.join_room(other.id, room.id)
      {:ok, message} = Messages.create_message(%{"content" => "Do autor"}, author.id, room.id)

      socket =
        %Phoenix.LiveView.Socket{private: %{lifecycle: %Phoenix.LiveView.Lifecycle{}}}
        |> assign(%{
          current_user: other,
          current_room: room,
          message_ids: MapSet.new([message.id]),
          message_map: %{message.id => message},
          message_order: [message.id],
          message_statuses: %{},
          oldest_message_id: nil,
          pending_messages: %{},
          online_users: [],
          typing_users: [],
          input_text: ""
        })
        |> Phoenix.LiveView.stream(:messages, [message])

      %{author: author, other: other, room: room, message: message, socket: socket}
    end

    test "start_edit_message only opens the dialog for the author's own message", %{
      author: author,
      message: message,
      socket: socket
    } do
      socket = assign(socket, current_user: author, current_room: %{id: message.room_id})

      assert {:noreply, updated_socket} =
               ChatLive.handle_event("start_edit_message", %{"message_id" => message.id}, socket)

      assert updated_socket.assigns.editing_message_id == message.id
      assert updated_socket.assigns.editing_content == "Do autor"
    end

    test "start_edit_message is ignored for another user's message", %{
      message: message,
      socket: socket
    } do
      assert {:noreply, updated_socket} =
               ChatLive.handle_event("start_edit_message", %{"message_id" => message.id}, socket)

      refute Map.get(updated_socket.assigns, :editing_message_id)
    end

    test "save_edit_message by a non-author does not persist", %{
      other: other,
      message: message,
      socket: socket
    } do
      socket =
        socket
        |> Phoenix.Component.assign(:editing_message_id, message.id)
        |> Phoenix.Component.assign(:editing_content, "Conteúdo forjado")

      assert {:noreply, updated_socket} =
               ChatLive.handle_event("save_edit_message", %{"message_id" => message.id}, socket)

      assert Map.get(updated_socket.assigns, :editing_message_id) == nil
      assert Messages.get_message(message.id).content == "Do autor"
      assert Messages.get_message(message.id).edited_at == nil
      assert other.id != message.user_id
    end

    test "handle_info updates the message in place for the selected room", %{
      author: author,
      message: message,
      socket: socket
    } do
      updated_message = %{message | content: "Novo conteúdo", edited_at: DateTime.utc_now()}

      socket = assign(socket, current_user: author)

      assert {:noreply, updated_socket} =
               ChatLive.handle_info({:message_updated, updated_message}, socket)

      assert updated_socket.assigns.message_map[message.id].content == "Novo conteúdo"
      assert updated_socket.assigns.message_map[message.id].edited_at != nil
    end

    test "handle_info ignores updates for rooms the user cannot access", %{
      other: other,
      socket: socket
    } do
      other_room = %{id: Ecto.UUID.generate()}
      socket = assign(socket, current_user: other, current_room: nil)

      assert {:noreply, updated_socket} =
               ChatLive.handle_info(
                 {:message_updated, %{room_id: other_room.id, id: Ecto.UUID.generate()}},
                 socket
               )

      assert updated_socket.assigns.current_room == nil
    end
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
