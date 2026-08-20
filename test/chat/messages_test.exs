defmodule Chat.MessagesTest do
  use Chat.DataCase, async: false

  import Ecto.Query
  import ExUnit.CaptureLog

  alias Chat.Auth.Identity
  alias Chat.Messages
  alias Chat.Messages.{Message, MessageRevision, ReadReceipt}
  alias Chat.Repo
  alias Chat.Rooms

  setup do
    {:ok, user} = Identity.sync_user(%{"sub" => "message-user"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Mensagens"}, user.id)

    Phoenix.PubSub.subscribe(Chat.PubSub, "room:#{room.id}")

    %{user: user, room: room}
  end

  test "create_message broadcasts after successful insert", %{user: user, room: room} do
    assert {:ok, message} =
             Messages.create_message(%{"content" => "Olá"}, user.id, room.id)

    assert_receive {:message_created, ^message}
  end

  test "create_message does not broadcast when insert fails", %{user: user, room: room} do
    assert {:error, %Ecto.Changeset{}} =
             Messages.create_message(%{"content" => ""}, user.id, room.id)

    refute_receive {:message_created, _}
  end

  test "create_message returns message with loaded user", %{user: user, room: room} do
    assert {:ok, message} =
             Messages.create_message(%{"content" => "Com usuário"}, user.id, room.id)

    assert message.user.id == user.id
    assert message.user.username == user.username
  end

  test "broadcast failure after commit does not turn persistence into an error", %{
    user: user,
    room: room
  } do
    log =
      capture_log(fn ->
        assert {:ok, message} =
                 Messages.create_message(
                   %{"content" => "Persistida sem PubSub"},
                   user.id,
                   room.id,
                   broadcaster: Chat.BroadcastFailureStub
                 )

        assert_receive {:broadcast_attempted, room_id, message_id}
        assert room_id == room.id
        assert message_id == message.id
        assert Messages.get_message(message.id)
        refute_receive {:message_created, _message}
      end)

    assert log =~ "message broadcast failed"
  end

  test "broadcast process exit after commit does not turn persistence into an error", %{
    user: user,
    room: room
  } do
    log =
      capture_log(fn ->
        assert {:ok, message} =
                 Messages.create_message(
                   %{"content" => "Persistida após exit"},
                   user.id,
                   room.id,
                   broadcaster: Chat.BroadcastExitStub
                 )

        assert_receive {:broadcast_exit_attempted, room_id, message_id}
        assert room_id == room.id
        assert message_id == message.id
        assert Messages.get_message(message.id)
        refute_receive {:message_created, _message}
      end)

    assert log =~ "message broadcast failed"
  end

  test "mention broadcast failure after commit does not turn persistence into an error", %{
    user: user,
    room: room
  } do
    {:ok, mentioned} = Identity.sync_user(%{"sub" => "mention-broadcast-failure-target"}, %{})
    assert {:ok, _membership} = Rooms.join_room(mentioned.id, room.id)

    log =
      capture_log(fn ->
        assert {:ok, message} =
                 Messages.create_message(
                   %{"content" => "Olá @#{mentioned.username}"},
                   user.id,
                   room.id,
                   broadcaster: Chat.BroadcastFailureStub
                 )

        assert_receive {:mention_broadcast_attempted, message_id, 1}
        assert message_id == message.id
        assert Messages.get_message(message.id)
      end)

    assert log =~ "mention broadcast failed"
  end

  test "successive messages preserve subsecond creation order", %{user: user, room: room} do
    assert {:ok, first} =
             Messages.create_message(
               %{"content" => "Primeira no mesmo segundo"},
               user.id,
               room.id
             )

    assert {:ok, second} =
             Messages.create_message(%{"content" => "Segunda no mesmo segundo"}, user.id, room.id)

    assert NaiveDateTime.compare(first.inserted_at, second.inserted_at) == :lt
    assert Enum.map(Messages.list_messages(room.id), & &1.id) == [first.id, second.id]
  end

  test "client_id makes repeated message creation idempotent", %{user: user, room: room} do
    client_id = Ecto.UUID.generate()
    attrs = %{"content" => "Envio idempotente"}

    assert {:ok, first} = Messages.create_message(attrs, user.id, room.id, client_id: client_id)
    assert_receive {:message_created, ^first}

    assert {:ok, repeated} =
             Messages.create_message(attrs, user.id, room.id, client_id: client_id)

    assert repeated.id == first.id
    assert repeated.client_id == client_id
    assert Messages.list_messages(room.id) |> Enum.map(& &1.id) == [first.id]
    refute_receive {:message_created, _message}
  end

  test "invalid client_id returns an explicit error without persisting", %{user: user, room: room} do
    assert {:error, :invalid_client_id} =
             Messages.create_message(
               %{"content" => "Cliente inválido"},
               user.id,
               room.id,
               client_id: "not-a-uuid"
             )

    assert Messages.list_messages(room.id) == []
    refute_receive {:message_created, _message}
  end

  test "reusing client_id with different content returns a conflict", %{
    user: user,
    room: room
  } do
    client_id = Ecto.UUID.generate()

    assert {:ok, original} =
             Messages.create_message(
               %{"content" => "Conteúdo original"},
               user.id,
               room.id,
               client_id: client_id
             )

    assert {:error, :client_id_conflict} =
             Messages.create_message(
               %{"content" => "Conteúdo diferente"},
               user.id,
               room.id,
               client_id: client_id
             )

    assert [persisted] = Messages.list_messages(room.id)
    assert persisted.id == original.id
    assert persisted.content == "Conteúdo original"
    refute_receive {:message_created, %{content: "Conteúdo diferente"}}
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

  test "get_message!/2 returns message when it belongs to the room", %{user: user, room: room} do
    assert {:ok, message} =
             Messages.create_message(%{"content" => "Na sala"}, user.id, room.id)

    assert fetched = Messages.get_message!(message.id, room.id)
    assert fetched.id == message.id
    assert fetched.user.id == user.id
  end

  test "get_message!/2 raises when message belongs to another room", %{user: user, room: room} do
    {:ok, other_room} = Chat.Rooms.create_room(%{"name" => "Outra"}, user.id)

    assert {:ok, message} =
             Messages.create_message(%{"content" => "Outra sala"}, user.id, other_room.id)

    assert_raise Ecto.NoResultsError, fn ->
      Messages.get_message!(message.id, room.id)
    end
  end

  test "get_message!/2 raises when message does not exist", %{room: room} do
    assert_raise Ecto.NoResultsError, fn ->
      Messages.get_message!(Ecto.UUID.generate(), room.id)
    end
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

  describe "edit_own_message/4" do
    test "updates content, records and preserves edited_at, and broadcasts", %{
      user: user,
      room: room
    } do
      assert {:ok, message} =
               Messages.create_message(%{"content" => "Versão original"}, user.id, room.id)

      room_id = room.id
      message_id = message.id

      assert {:ok, edited} =
               Messages.edit_own_message(
                 message_id,
                 user.id,
                 room_id,
                 %{"content" => "Versão editada"}
               )

      assert edited.id == message_id
      assert edited.content == "Versão editada"
      assert edited.inserted_at == message.inserted_at
      assert edited.edited_at != nil
      assert_receive {:message_updated, ^edited}

      assert fetched = Messages.get_message(message_id)
      assert fetched.content == "Versão editada"
      assert fetched.edited_at != nil
      assert fetched.inserted_at == message.inserted_at

      revisions =
        Repo.all(
          from revision in MessageRevision,
            where: revision.message_id == ^message_id,
            select: %{
              message_id: revision.message_id,
              content: revision.content,
              editor_id: revision.editor_id
            }
        )

      assert [%{message_id: ^message_id, content: "Versão original", editor_id: editor_id}] =
               revisions

      assert editor_id == user.id
    end

    test "preserves every previous version across successive edits", %{user: user, room: room} do
      assert {:ok, message} =
               Messages.create_message(%{"content" => "Versão 1"}, user.id, room.id)

      assert {:ok, _edited} =
               Messages.edit_own_message(message.id, user.id, room.id, %{
                 "content" => "Versão 2"
               })

      assert {:ok, _edited} =
               Messages.edit_own_message(message.id, user.id, room.id, %{
                 "content" => "Versão 3"
               })

      revisions =
        Repo.all(
          from revision in MessageRevision,
            where: revision.message_id == ^message.id,
            order_by: [asc: revision.inserted_at],
            select: revision.content
        )

      assert revisions == ["Versão 1", "Versão 2"]
      assert Messages.get_message(message.id).content == "Versão 3"
    end

    test "rejects a user who is not the author", %{user: user, room: room} do
      {:ok, other_user} = Identity.sync_user(%{"sub" => "edit-other-user"}, %{})
      assert {:ok, _membership} = Rooms.join_room(other_user.id, room.id)

      assert {:ok, message} =
               Messages.create_message(%{"content" => "Do autor"}, user.id, room.id)

      assert {:error, :not_authorized} =
               Messages.edit_own_message(message.id, other_user.id, room.id, %{
                 "content" => "Invasão"
               })

      assert Messages.get_message(message.id).content == "Do autor"
      refute_receive {:message_updated, _}
    end

    test "rejects a user who is not a member", %{user: user, room: room} do
      {:ok, outsider} = Identity.sync_user(%{"sub" => "edit-outsider"}, %{})

      assert {:ok, message} =
               Messages.create_message(%{"content" => "Na sala"}, user.id, room.id)

      assert {:error, :not_member} =
               Messages.edit_own_message(message.id, outsider.id, room.id, %{
                 "content" => "X"
               })
    end

    test "rejects a deleted message without broadcasting", %{user: user, room: room} do
      assert {:ok, message} =
               Messages.create_message(%{"content" => "Será excluída"}, user.id, room.id)

      assert {:ok, _deleted} = Messages.delete_message(message)

      assert {:error, :not_found} =
               Messages.edit_own_message(message.id, user.id, room.id, %{
                 "content" => "Ressuscitar"
               })

      refute_receive {:message_updated, _}
    end

    test "rejects a message from another room", %{user: user, room: room} do
      {:ok, other_room} = Chat.Rooms.create_room(%{"name" => "Outra sala"}, user.id)

      assert {:ok, message} =
               Messages.create_message(%{"content" => "Outra sala"}, user.id, other_room.id)

      assert {:error, :not_found} =
               Messages.edit_own_message(message.id, user.id, room.id, %{"content" => "X"})
    end

    test "rejects invalid content and keeps the original", %{user: user, room: room} do
      assert {:ok, message} =
               Messages.create_message(%{"content" => "Válida"}, user.id, room.id)

      assert {:error, %Ecto.Changeset{}} =
               Messages.edit_own_message(message.id, user.id, room.id, %{"content" => ""})

      assert Messages.get_message(message.id).content == "Válida"
      assert Messages.get_message(message.id).edited_at == nil
      refute_receive {:message_updated, _}
    end

    test "unchanged content returns the message without marking it as edited", %{
      user: user,
      room: room
    } do
      assert {:ok, message} =
               Messages.create_message(%{"content" => "Igual"}, user.id, room.id)

      assert {:ok, unchanged} =
               Messages.edit_own_message(message.id, user.id, room.id, %{"content" => "Igual"})

      assert unchanged.id == message.id
      assert unchanged.edited_at == nil

      assert Repo.all(from revision in MessageRevision, where: revision.message_id == ^message.id) ==
               []

      refute_receive {:message_updated, _}
    end

    test "reconciles mentions when content changes", %{user: user, room: room} do
      {:ok, first_mentioned} = Identity.sync_user(%{"sub" => "edit-mention-first"}, %{})
      {:ok, second_mentioned} = Identity.sync_user(%{"sub" => "edit-mention-second"}, %{})
      assert {:ok, _membership} = Rooms.join_room(first_mentioned.id, room.id)
      assert {:ok, _membership} = Rooms.join_room(second_mentioned.id, room.id)

      assert {:ok, message} =
               Messages.create_message(
                 %{"content" => "Olá @#{first_mentioned.username}"},
                 user.id,
                 room.id
               )

      room_id = room.id
      message_id = message.id
      user_id = user.id

      Phoenix.PubSub.subscribe(Chat.PubSub, "user:#{first_mentioned.id}")
      Phoenix.PubSub.subscribe(Chat.PubSub, "user:#{second_mentioned.id}")

      assert {:ok, edited} =
               Messages.edit_own_message(
                 message_id,
                 user.id,
                 room_id,
                 %{"content" => "Olá @#{second_mentioned.username}"}
               )

      assert [mention] = edited.mentions
      assert mention.mentioned_user_id == second_mentioned.id
      assert mention.start_offset == 5

      assert_receive {:mention_deleted, %{message_id: ^message_id, room_id: ^room_id}}

      assert_receive {:mention_created,
                      %{message_id: ^message_id, room_id: ^room_id, sender_id: ^user_id}}
    end

    test "keeps existing mentions without re-broadcasting when they do not change", %{
      user: user,
      room: room
    } do
      {:ok, mentioned} = Identity.sync_user(%{"sub" => "edit-mention-keep"}, %{})
      assert {:ok, _membership} = Rooms.join_room(mentioned.id, room.id)

      assert {:ok, message} =
               Messages.create_message(
                 %{"content" => "Olá @#{mentioned.username}, tudo bem?"},
                 user.id,
                 room.id
               )

      Phoenix.PubSub.subscribe(Chat.PubSub, "user:#{mentioned.id}")

      assert {:ok, edited} =
               Messages.edit_own_message(
                 message.id,
                 user.id,
                 room.id,
                 %{"content" => "Olá @#{mentioned.username}, como vai?"}
               )

      assert [mention] = edited.mentions
      assert mention.mentioned_user_id == mentioned.id
      refute_receive {:mention_created, _}
      refute_receive {:mention_deleted, _}
    end

    test "edit broadcast failure after commit does not turn persistence into an error", %{
      user: user,
      room: room
    } do
      assert {:ok, message} =
               Messages.create_message(%{"content" => "Original"}, user.id, room.id)

      log =
        capture_log(fn ->
          assert {:ok, _edited} =
                   Messages.edit_own_message(
                     message.id,
                     user.id,
                     room.id,
                     %{"content" => "Editada"},
                     broadcaster: Chat.BroadcastFailureStub
                   )

          assert_receive {:edit_broadcast_attempted, room_id, message_id}
          assert room_id == room.id
          assert message_id == message.id
          assert Messages.get_message(message.id).content == "Editada"
          refute_receive {:message_updated, _message}
        end)

      assert log =~ "message broadcast failed"
    end
  end

  test "delivery_status/3 returns :read when another user read the message", %{
    user: user,
    room: room
  } do
    assert {:ok, message} =
             Messages.create_message(%{"content" => "Lida"}, user.id, room.id)

    {:ok, reader} = Identity.sync_user(%{"sub" => "delivery-reader"}, %{})
    assert :ok = Messages.mark_as_read(message.id, reader.id)

    assert Messages.delivery_status(message.id, user.id, []) == :read
    assert Messages.delivery_status(message.id, user.id, [reader.id]) == :read
  end

  test "delivery_status/3 returns :delivered when another user is online but has not read", %{
    user: user,
    room: room
  } do
    assert {:ok, message} =
             Messages.create_message(%{"content" => "Entregue"}, user.id, room.id)

    {:ok, other} = Identity.sync_user(%{"sub" => "delivery-online"}, %{})

    assert Messages.delivery_status(message.id, user.id, [other.id]) == :delivered
  end

  test "delivery_status/3 returns :sent when no one else is online and no one read", %{
    user: user,
    room: room
  } do
    assert {:ok, message} =
             Messages.create_message(%{"content" => "Enviada"}, user.id, room.id)

    assert Messages.delivery_status(message.id, user.id, []) == :sent
    assert Messages.delivery_status(message.id, user.id, [user.id]) == :sent
  end

  test "message_status/2 returns :read when read_count > 0" do
    assert Messages.message_status(1, 0) == :read
    assert Messages.message_status(1, 2) == :read
  end

  test "message_status/2 returns :delivered when delivered_count > 0 and read_count == 0" do
    assert Messages.message_status(0, 1) == :delivered
    assert Messages.message_status(0, 2) == :delivered
  end

  test "message_status/2 returns :sent when both counts are zero" do
    assert Messages.message_status(0, 0) == :sent
  end

  test "readers_tooltip/2 shows sent message when no readers and no deliveries", %{
    user: user,
    room: room
  } do
    assert {:ok, message} =
             Messages.create_message(%{"content" => "Sem leitura"}, user.id, room.id)

    assert Messages.readers_tooltip(message.id, user.id, 0) == "Enviada"
  end

  test "readers_tooltip/2 shows delivered count when not read", %{user: user, room: room} do
    assert {:ok, message} =
             Messages.create_message(%{"content" => "Entregue"}, user.id, room.id)

    assert Messages.readers_tooltip(message.id, user.id, 2) == "Entregue a 2 pessoa(s)"
  end

  test "readers_tooltip/2 shows reader names when read by others", %{user: user, room: room} do
    assert {:ok, message} =
             Messages.create_message(%{"content" => "Lida"}, user.id, room.id)

    {:ok, reader} =
      Identity.sync_user(%{"sub" => "tooltip-reader"}, %{"username" => "tooltip-reader"})

    assert :ok = Messages.mark_as_read(message.id, reader.id)

    assert Messages.readers_tooltip(message.id, user.id, 1) == "Lida por: tooltip-reader"
  end

  defp receipt_count(message_id, user_id) do
    ReadReceipt
    |> where([receipt], receipt.message_id == ^message_id and receipt.user_id == ^user_id)
    |> Repo.aggregate(:count)
  end
end
