defmodule Chat.Messages.MentionsTest do
  use Chat.DataCase, async: false

  alias Chat.Auth.Identity
  alias Chat.Messages
  alias Chat.Rooms

  setup do
    {:ok, author} = Identity.sync_user(%{"sub" => "mention-author"}, %{})
    {:ok, mentioned} = Identity.sync_user(%{"sub" => "mention-target"}, %{})
    {:ok, outsider} = Identity.sync_user(%{"sub" => "mention-outsider"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Menções"}, author.id)
    {:ok, _membership} = Rooms.join_room(mentioned.id, room.id)

    %{author: author, mentioned: mentioned, outsider: outsider, room: room}
  end

  test "notification limit applies to distinct messages rather than mention occurrences", %{
    author: author,
    mentioned: mentioned,
    room: room
  } do
    assert {:ok, older} =
             Messages.create_message(
               %{"content" => "Primeiro @#{mentioned.username}"},
               author.id,
               room.id
             )

    assert {:ok, newer} =
             Messages.create_message(
               %{
                 "content" => "Depois @#{mentioned.username}, novamente @#{mentioned.username}"
               },
               author.id,
               room.id
             )

    assert [first, second] = Messages.list_mention_notifications(mentioned.id, limit: 2)
    assert [first.message_id, second.message_id] == [newer.id, older.id]
  end

  test "fetching a notification requires current room membership", %{
    author: author,
    mentioned: mentioned,
    room: room
  } do
    assert {:ok, message} =
             Messages.create_message(
               %{"content" => "Atenção @#{mentioned.username}"},
               author.id,
               room.id
             )

    assert {:ok, notification} =
             Messages.get_mention_notification(mentioned.id, message.id)

    assert notification.message_id == message.id
    assert notification.message.room.id == room.id

    assert {:ok, 1} = Rooms.leave_room(mentioned.id, room.id)
    assert {:error, :not_found} = Messages.get_mention_notification(mentioned.id, message.id)
    assert {:error, :invalid_id} = Messages.get_mention_notification(mentioned.id, %{})
  end

  test "self mentions remain structural but are excluded from notifications", %{
    author: author,
    room: room
  } do
    assert {:ok, message} =
             Messages.create_message(
               %{"content" => "Lembrete @#{author.username}"},
               author.id,
               room.id
             )

    assert [%{mentioned_user_id: mentioned_user_id}] = message.mentions
    assert mentioned_user_id == author.id
    assert Messages.list_mention_notifications(author.id) == []
    assert {:error, :not_found} = Messages.get_mention_notification(author.id, message.id)
  end

  test "persists member mention occurrences with the message", %{
    author: author,
    mentioned: mentioned,
    room: room
  } do
    content = "Olá @#{mentioned.username}, revise com @#{mentioned.username}."

    assert {:ok, message} = Messages.create_message(%{"content" => content}, author.id, room.id)
    assert [first, second] = message.mentions
    assert Enum.all?([first, second], &(&1.mentioned_user_id == mentioned.id))

    assert Enum.map([first, second], & &1.username_snapshot) ==
             [mentioned.username, mentioned.username]

    assert first.start_offset < second.start_offset

    assert [loaded] = Messages.list_messages(room.id)
    assert Enum.map(loaded.mentions, & &1.id) == Enum.map(message.mentions, & &1.id)
  end

  test "persists a quoted mention for a member whose username contains spaces", %{
    author: author,
    room: room
  } do
    {:ok, mentioned} =
      Identity.sync_user(
        %{"sub" => "mention-full-name-target"},
        %{"username" => "VANESSA SOUSA DE PAIVA"}
      )

    assert {:ok, _membership} = Rooms.join_room(mentioned.id, room.id)

    assert {:ok, message} =
             Messages.create_message(
               %{"content" => ~s(Olá @"VANESSA SOUSA DE PAIVA"!)},
               author.id,
               room.id
             )

    assert [mention] = message.mentions
    assert mention.mentioned_user_id == mentioned.id
    assert mention.username_snapshot == mentioned.username

    assert binary_part(message.content, mention.start_offset, mention.length) ==
             ~s(@"VANESSA SOUSA DE PAIVA")
  end

  test "resolves Unicode case mappings independently from database collation", %{
    author: author,
    room: room
  } do
    {:ok, mentioned} =
      Identity.sync_user(
        %{"sub" => "mention-unicode-case-target"},
        %{"username" => "İpek"}
      )

    assert {:ok, _membership} = Rooms.join_room(mentioned.id, room.id)

    assert {:ok, message} =
             Messages.create_message(%{"content" => "Olá @İpek"}, author.id, room.id)

    assert [%{mentioned_user_id: mentioned_user_id}] = message.mentions
    assert mentioned_user_id == mentioned.id
  end

  test "persists only mentions targeting current room members", %{
    author: author,
    mentioned: mentioned,
    outsider: outsider,
    room: room
  } do
    content = "@#{mentioned.username} e @#{outsider.username}"

    assert {:ok, message} = Messages.create_message(%{"content" => content}, author.id, room.id)
    assert [%{mentioned_user_id: mentioned_id}] = message.mentions
    assert mentioned_id == mentioned.id
  end

  test "message creation enforces sender membership in the context", %{
    outsider: outsider,
    room: room
  } do
    assert {:error, :forbidden} =
             Messages.create_message(%{"content" => "Envio forjado"}, outsider.id, room.id)

    assert Messages.list_messages(room.id) == []
  end

  test "rejects malformed sender and room ids without raising", %{author: author, room: room} do
    assert {:error, :forbidden} =
             Messages.create_message(%{"content" => "Inválida"}, "not-a-uuid", room.id)

    assert {:error, :forbidden} =
             Messages.create_message(%{"content" => "Inválida"}, author.id, "not-a-uuid")
  end

  test "list_mentions returns active messages only for the addressed member", %{
    author: author,
    mentioned: mentioned,
    outsider: outsider,
    room: room
  } do
    assert {:ok, message} =
             Messages.create_message(
               %{"content" => "Atenção @#{mentioned.username}"},
               author.id,
               room.id
             )

    assert [mention] = Messages.list_mentions(mentioned.id)
    assert mention.message.id == message.id
    assert mention.message.user.id == author.id
    assert mention.message.room.id == room.id
    assert Messages.list_mentions(outsider.id) == []

    assert {:ok, _deleted} = Messages.delete_message(message)
    assert Messages.list_mentions(mentioned.id) == []
  end

  test "idempotent retry does not duplicate mentions", %{
    author: author,
    mentioned: mentioned,
    room: room
  } do
    client_id = Ecto.UUID.generate()
    attrs = %{"content" => "Revise @#{mentioned.username}"}

    assert {:ok, first} = Messages.create_message(attrs, author.id, room.id, client_id: client_id)

    assert {:ok, repeated} =
             Messages.create_message(attrs, author.id, room.id, client_id: client_id)

    assert repeated.id == first.id
    assert [mention] = Messages.list_mentions(mentioned.id)
    assert mention.message_id == first.id
  end

  test "idempotent retry reauthorizes a sender who left the room", %{room: room} do
    {:ok, sender} = Identity.sync_user(%{"sub" => "mention-idempotent-sender"}, %{})
    assert {:ok, _membership} = Rooms.join_room(sender.id, room.id)
    client_id = Ecto.UUID.generate()
    attrs = %{"content" => "Mensagem idempotente"}

    assert {:ok, _message} =
             Messages.create_message(attrs, sender.id, room.id, client_id: client_id)

    assert {:ok, 1} = Rooms.leave_room(sender.id, room.id)

    assert {:error, :forbidden} =
             Messages.create_message(attrs, sender.id, room.id, client_id: client_id)
  end

  test "unread count deduplicates occurrences and follows the room read position", %{
    author: author,
    mentioned: mentioned,
    room: room
  } do
    assert {:ok, message} =
             Messages.create_message(
               %{"content" => "@#{mentioned.username}, confirme com @#{mentioned.username}"},
               author.id,
               room.id
             )

    assert Messages.count_unread_mentions(mentioned.id) == 1

    assert {:ok, _position} =
             Messages.advance_room_read_position(mentioned.id, room.id, [message.id])

    assert Messages.count_unread_mentions(mentioned.id) == 0
  end

  test "unread mention counts are grouped by room", %{
    author: author,
    mentioned: mentioned,
    room: room
  } do
    {:ok, second_room} = Rooms.create_room(%{"name" => "Outra sala"}, author.id)
    assert {:ok, _membership} = Rooms.join_room(mentioned.id, second_room.id)

    assert {:ok, first_message} =
             Messages.create_message(%{"content" => "@#{mentioned.username}"}, author.id, room.id)

    assert {:ok, second_message} =
             Messages.create_message(
               %{"content" => "@#{mentioned.username}"},
               author.id,
               second_room.id
             )

    assert Messages.unread_mention_counts_by_room(mentioned.id, [room.id, second_room.id]) == %{
             room.id => 1,
             second_room.id => 1
           }

    assert {:ok, _position} =
             Messages.advance_room_read_position(mentioned.id, room.id, [first_message.id])

    assert Messages.unread_mention_counts_by_room(mentioned.id, [room.id, second_room.id]) == %{
             second_room.id => 1
           }

    assert second_message.id != first_message.id
  end

  test "broadcasts one personal event per mentioned user", %{
    author: author,
    mentioned: mentioned,
    room: room
  } do
    Phoenix.PubSub.subscribe(Chat.PubSub, "user:#{mentioned.id}")

    assert {:ok, message} =
             Messages.create_message(
               %{"content" => "@#{mentioned.username} e @#{mentioned.username}"},
               author.id,
               room.id
             )

    assert_receive {:mention_created,
                    %{message_id: message_id, room_id: room_id, sender_id: sender_id}}

    assert message_id == message.id
    assert room_id == room.id
    assert sender_id == author.id
    refute_receive {:mention_created, _payload}

    assert {:ok, _deleted} = Messages.delete_message(message)

    assert_receive {:mention_deleted, %{message_id: deleted_message_id}}
    assert deleted_message_id == message.id
  end
end
