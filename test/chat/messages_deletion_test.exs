defmodule Chat.MessagesDeletionTest do
  use Chat.DataCase, async: false

  alias Chat.Auth.Identity
  alias Chat.Messages
  alias Chat.Messages.Message
  alias Chat.Repo
  alias Chat.Rooms

  setup do
    {:ok, user} = Identity.sync_user(%{"sub" => "message-user"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Mensagens"}, user.id)

    Phoenix.PubSub.subscribe(Chat.PubSub, "room:#{room.id}")

    %{user: user, room: room}
  end

  test "delete_message broadcasts when room still exists", %{user: user, room: room} do
    assert {:ok, message} =
             Messages.create_message(%{"content" => "Para deletar"}, user.id, room.id)

    room_id = room.id
    message_id = message.id

    assert {:ok, deleted} = Messages.delete_message(message)
    assert deleted.id == message.id
    assert_receive {:message_deleted, ^room_id, ^message_id}
  end

  test "delete_message keeps the row and hides it from message queries", %{
    user: user,
    room: room
  } do
    assert {:ok, message} =
             Messages.create_message(%{"content" => "Exclusão lógica"}, user.id, room.id)

    assert {:ok, _deleted} = Messages.delete_message(message)

    assert %Message{} = stored_message = Repo.get(Message, message.id)
    assert Map.get(stored_message, :deleted_at)
    assert Messages.get_message(message.id) == nil
    assert Messages.list_messages(room.id) == []
    assert Messages.get_room_messages_count(room.id) == 0

    assert_raise Ecto.NoResultsError, fn ->
      Messages.get_message!(message.id, room.id)
    end
  end

  test "delete_message skips broadcast when room was deleted", %{user: user, room: room} do
    assert {:ok, message} =
             Messages.create_message(%{"content" => "Sala sumiu"}, user.id, room.id)

    # Simulate the room being deleted (cascade-deletes messages).
    assert {:ok, _} = Chat.Rooms.delete_room(room)

    # The in-memory message struct still exists, but the DB row is gone.
    assert {:ok, deleted} = Messages.delete_message(message)
    assert deleted.id == message.id
    refute_receive {:message_deleted, _, _}
  end

  test "delete_message_if_unread/2 deletes when unread", %{user: user, room: room} do
    assert {:ok, message} =
             Messages.create_message(%{"content" => "Não lida"}, user.id, room.id)

    assert {:ok, _} = Messages.delete_message_if_unread(message, user.id)
    assert Messages.get_message(message.id) == nil
  end

  test "delete_message_if_unread/2 blocks deletion when read by others", %{
    user: user,
    room: room
  } do
    assert {:ok, message} =
             Messages.create_message(%{"content" => "Lida"}, user.id, room.id)

    {:ok, reader} = Identity.sync_user(%{"sub" => "reader-block"}, %{})
    assert :ok = Messages.mark_as_read(message.id, reader.id)

    assert {:error, :already_read} = Messages.delete_message_if_unread(message, user.id)
    assert Messages.get_message(message.id) != nil
  end

  test "delete_message_if_unread/2 blocks deletion when another member's read position includes it",
       %{
         user: author,
         room: room
       } do
    {:ok, reader} = Identity.sync_user(%{"sub" => "position-delete-reader"}, %{})
    assert {:ok, _membership} = Rooms.join_room(reader.id, room.id)

    assert {:ok, message} =
             Messages.create_message(%{"content" => "Lida pelo cursor"}, author.id, room.id)

    assert {:ok, _position} =
             Messages.advance_room_read_position(reader.id, room.id, [message.id])

    assert {:error, :already_read} = Messages.delete_message_if_unread(message, author.id)
    assert Messages.get_message(message.id)
  end

  test "delete_own_unread_message/3 rejects a user who is not the author", %{
    user: author,
    room: room
  } do
    {:ok, other_user} = Identity.sync_user(%{"sub" => "delete-other-user"}, %{})
    assert {:ok, _membership} = Rooms.join_room(other_user.id, room.id)

    assert {:ok, message} =
             Messages.create_message(%{"content" => "Mensagem do autor"}, author.id, room.id)

    assert {:error, :not_authorized} =
             Messages.delete_own_unread_message(message.id, other_user.id, room.id)

    assert Messages.get_message(message.id)
  end
end
