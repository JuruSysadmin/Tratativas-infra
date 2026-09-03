defmodule Chat.MessagesReadTrackingTest do
  use Chat.DataCase, async: false

  import Ecto.Query
  alias Chat.Auth.Identity
  alias Chat.Messages
  alias Chat.Messages.{Message, ReadReceipt}
  alias Chat.Repo
  alias Chat.Rooms

  setup do
    {:ok, user} = Identity.sync_user(%{"sub" => "message-user"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Mensagens"}, user.id)

    Phoenix.PubSub.subscribe(Chat.PubSub, "room:#{room.id}")

    %{user: user, room: room}
  end

  test "mark_as_read/2 marks a message as read", %{user: user, room: room} do
    assert {:ok, message} =
             Messages.create_message(%{"content" => "Para ler"}, user.id, room.id)

    {:ok, reader} = Identity.sync_user(%{"sub" => "reader-mark"}, %{})

    assert :ok = Messages.mark_as_read(message.id, reader.id)
    assert Messages.someone_read?(message.id, user.id)
  end

  test "mark_as_read/2 returns :already_read on duplicate", %{user: user, room: room} do
    assert {:ok, message} =
             Messages.create_message(%{"content" => "Para ler"}, user.id, room.id)

    {:ok, reader} = Identity.sync_user(%{"sub" => "reader-dup"}, %{})

    assert :ok = Messages.mark_as_read(message.id, reader.id)
    assert :already_read = Messages.mark_as_read(message.id, reader.id)
  end

  test "re-reading the same message keeps one receipt and read count at one", %{
    user: author,
    room: room
  } do
    assert {:ok, message} =
             Messages.create_message(%{"content" => "Releitura individual"}, author.id, room.id)

    {:ok, reader} = Identity.sync_user(%{"sub" => "reader-reconnect"}, %{})

    assert :ok = Messages.mark_as_read(message.id, reader.id)
    assert :already_read = Messages.mark_as_read(message.id, reader.id)
    assert :already_read = Messages.mark_as_read(message.id, reader.id)

    assert receipt_count(message.id, reader.id) == 1
    assert Messages.read_count(message.id, author.id) == 1
    assert [%{user_id: reader_id}] = Messages.list_readers(message.id)
    assert reader_id == reader.id
  end

  test "mark_as_read_bulk/2 marks multiple messages as read", %{user: user, room: room} do
    assert {:ok, msg1} = Messages.create_message(%{"content" => "M1"}, user.id, room.id)
    assert {:ok, msg2} = Messages.create_message(%{"content" => "M2"}, user.id, room.id)

    {:ok, reader} = Identity.sync_user(%{"sub" => "reader-bulk"}, %{})

    Messages.mark_as_read_bulk([msg1.id, msg2.id], reader.id)

    assert Messages.someone_read?(msg1.id, user.id)
    assert Messages.someone_read?(msg2.id, user.id)
  end

  test "bulk re-read ignores duplicate ids and does not inflate read count", %{
    user: author,
    room: room
  } do
    assert {:ok, message} =
             Messages.create_message(%{"content" => "Releitura em lote"}, author.id, room.id)

    {:ok, reader} = Identity.sync_user(%{"sub" => "reader-bulk-reconnect"}, %{})
    assert {:ok, _membership} = Rooms.join_room(reader.id, room.id)

    duplicate_ids = [message.id, message.id, message.id]

    assert [message_id] =
             Messages.mark_room_messages_as_read(duplicate_ids, reader.id, room.id)

    assert message_id == message.id
    assert [] = Messages.mark_room_messages_as_read(duplicate_ids, reader.id, room.id)

    assert receipt_count(message.id, reader.id) == 1
    assert Messages.read_count(message.id, author.id) == 1
  end

  test "room read position persists unread counts", %{user: author, room: room} do
    {:ok, reader} = Identity.sync_user(%{"sub" => "persistent-unread-reader"}, %{})
    assert {:ok, _membership} = Rooms.join_room(reader.id, room.id)

    assert {:ok, first} =
             Messages.create_message(%{"content" => "Primeira não lida"}, author.id, room.id)

    assert {:ok, second} =
             Messages.create_message(%{"content" => "Segunda não lida"}, author.id, room.id)

    assert %{room.id => 2} == Messages.unread_counts_by_room(reader.id, [room.id])

    assert {:ok, position} =
             Messages.advance_room_read_position(reader.id, room.id, [first.id, second.id])

    assert position.last_read_message_id == second.id
    assert %{} == Messages.unread_counts_by_room(reader.id, [room.id])

    assert {:ok, _third} =
             Messages.create_message(%{"content" => "Terceira não lida"}, author.id, room.id)

    assert %{room.id => 1} == Messages.unread_counts_by_room(reader.id, [room.id])
  end

  test "room read position does not regress to an older message", %{user: author, room: room} do
    {:ok, reader} = Identity.sync_user(%{"sub" => "monotonic-position-reader"}, %{})
    assert {:ok, _membership} = Rooms.join_room(reader.id, room.id)

    assert {:ok, first} = Messages.create_message(%{"content" => "Primeira"}, author.id, room.id)
    assert {:ok, second} = Messages.create_message(%{"content" => "Segunda"}, author.id, room.id)
    assert {:ok, _third} = Messages.create_message(%{"content" => "Terceira"}, author.id, room.id)

    assert {:ok, position} =
             Messages.advance_room_read_position(reader.id, room.id, [second.id])

    assert position.last_read_message_id == second.id

    assert {:ok, position} =
             Messages.advance_room_read_position(reader.id, room.id, [first.id])

    assert position.last_read_message_id == second.id
    assert Messages.unread_counts_by_room(reader.id, [room.id]) == %{room.id => 1}
  end

  test "room read position rejects messages outside the member room", %{
    user: author,
    room: room
  } do
    {:ok, reader} = Identity.sync_user(%{"sub" => "scoped-position-reader"}, %{})
    assert {:ok, _membership} = Rooms.join_room(reader.id, room.id)
    assert {:ok, other_room} = Rooms.create_room(%{"name" => "Outra posição"}, author.id)

    assert {:ok, other_message} =
             Messages.create_message(%{"content" => "Outra sala"}, author.id, other_room.id)

    assert {:error, :not_found} =
             Messages.advance_room_read_position(reader.id, room.id, [other_message.id])

    assert {:error, :not_found} =
             Messages.advance_room_read_position(reader.id, other_room.id, [other_message.id])
  end

  test "someone_read?/2 ignores the sender", %{user: user, room: room} do
    assert {:ok, message} =
             Messages.create_message(%{"content" => "Ignorar remetente"}, user.id, room.id)

    assert :ok = Messages.mark_as_read(message.id, user.id)
    refute Messages.someone_read?(message.id, user.id)
  end

  test "someone_read?/2 detects another reader", %{user: user, room: room} do
    assert {:ok, message} =
             Messages.create_message(%{"content" => "Outro leitor"}, user.id, room.id)

    {:ok, reader} = Identity.sync_user(%{"sub" => "reader"}, %{})
    assert :ok = Messages.mark_as_read(message.id, reader.id)
    assert Messages.someone_read?(message.id, user.id)
  end

  test "read_count/2 counts readers excluding sender", %{user: user, room: room} do
    assert {:ok, message} =
             Messages.create_message(%{"content" => "Contagem"}, user.id, room.id)

    {:ok, reader1} = Identity.sync_user(%{"sub" => "reader-1"}, %{})
    {:ok, reader2} = Identity.sync_user(%{"sub" => "reader-2"}, %{})

    Messages.mark_as_read(message.id, user.id)
    Messages.mark_as_read(message.id, reader1.id)
    Messages.mark_as_read(message.id, reader2.id)

    assert Messages.read_count(message.id, user.id) == 2
  end

  test "load_read_metadata/1 recognizes a reader whose room cursor reached the message", %{
    user: author,
    room: room
  } do
    {:ok, reader} = Identity.sync_user(%{"sub" => "position-metadata-reader"}, %{})
    assert {:ok, _membership} = Rooms.join_room(reader.id, room.id)

    assert {:ok, message} =
             Messages.create_message(%{"content" => "Lida pelo cursor"}, author.id, room.id)

    assert {:ok, _position} =
             Messages.advance_room_read_position(reader.id, room.id, [message.id])

    [loaded_message] = Messages.load_read_metadata([message])

    assert Messages.read_count(message.id, author.id) == 1
    assert loaded_message.read_count == 1
    assert loaded_message.reader_names == [reader.username]
  end

  test "delivery_count/2 counts another member whose delivery cursor reached the message", %{
    user: author,
    room: room
  } do
    {:ok, recipient} = Identity.sync_user(%{"sub" => "delivery-cursor-recipient"}, %{})
    assert {:ok, _membership} = Rooms.join_room(recipient.id, room.id)

    assert {:ok, message} =
             Messages.create_message(%{"content" => "Entregue pelo cursor"}, author.id, room.id)

    assert {:ok, _position} =
             Messages.advance_room_delivery_position(recipient.id, room.id, [message.id])

    [loaded_message] = Messages.load_delivery_metadata([message])

    assert Messages.delivery_count(message.id, author.id) == 1
    assert loaded_message.delivered_count == 1
  end

  test "list_readers/1 returns readers and timestamps", %{user: user, room: room} do
    assert {:ok, message} =
             Messages.create_message(%{"content" => "Leitores"}, user.id, room.id)

    {:ok, reader} = Identity.sync_user(%{"sub" => "reader-list"}, %{})
    assert :ok = Messages.mark_as_read(message.id, reader.id)

    reader_id = reader.id

    assert [%{user_id: ^reader_id, username: "reader-list", read_at: _}] =
             Messages.list_readers(message.id)
  end

  defp receipt_count(message_id, user_id) do
    ReadReceipt
    |> where([receipt], receipt.message_id == ^message_id and receipt.user_id == ^user_id)
    |> Repo.aggregate(:count)
  end

  test "soft deleting the cursor message preserves the unread boundary", %{
    user: author,
    room: room
  } do
    {:ok, reader} = Identity.sync_user(%{"sub" => "deleted-cursor-reader"}, %{})
    assert {:ok, _membership} = Rooms.join_room(reader.id, room.id)
    assert {:ok, _first} = Messages.create_message(%{"content" => "Antes"}, author.id, room.id)
    assert {:ok, cursor} = Messages.create_message(%{"content" => "Cursor"}, author.id, room.id)

    assert {:ok, _position} =
             Messages.advance_room_read_position(reader.id, room.id, [cursor.id])

    assert {:ok, _deleted} = Messages.delete_message(cursor)
    assert {:ok, _newer} = Messages.create_message(%{"content" => "Depois"}, author.id, room.id)

    assert Messages.unread_counts_by_room(reader.id, [room.id]) == %{room.id => 1}
  end

  test "hard deleting the cursor message preserves the unread boundary", %{
    user: author,
    room: room
  } do
    {:ok, reader} = Identity.sync_user(%{"sub" => "purged-cursor-reader"}, %{})
    assert {:ok, _membership} = Rooms.join_room(reader.id, room.id)
    assert {:ok, _first} = Messages.create_message(%{"content" => "Antes"}, author.id, room.id)

    assert {:ok, cursor} =
             Messages.create_message(%{"content" => "Cursor purgado"}, author.id, room.id)

    assert {:ok, _position} =
             Messages.advance_room_read_position(reader.id, room.id, [cursor.id])

    assert %Message{} = Repo.delete!(cursor)
    assert {:ok, _newer} = Messages.create_message(%{"content" => "Depois"}, author.id, room.id)

    assert Messages.unread_counts_by_room(reader.id, [room.id]) == %{room.id => 1}
  end
end
