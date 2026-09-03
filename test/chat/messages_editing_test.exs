defmodule Chat.MessagesEditingTest do
  use Chat.DataCase, async: false

  import Ecto.Query
  import ExUnit.CaptureLog
  alias Chat.Auth.Identity
  alias Chat.Messages
  alias Chat.Messages.MessageRevision
  alias Chat.Repo
  alias Chat.Rooms

  setup do
    {:ok, user} = Identity.sync_user(%{"sub" => "message-user"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Mensagens"}, user.id)

    Phoenix.PubSub.subscribe(Chat.PubSub, "room:#{room.id}")

    %{user: user, room: room}
  end

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
