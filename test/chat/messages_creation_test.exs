defmodule Chat.MessagesCreationTest do
  use Chat.DataCase, async: false

  import ExUnit.CaptureLog
  alias Chat.Auth.Identity
  alias Chat.Messages
  alias Chat.Repo
  alias Chat.Rooms
  alias Ecto.Adapters.SQL.Sandbox

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

  test "broadcast callback sees the message after its transaction is committed", %{
    room: _room
  } do
    {user, room, message} =
      Sandbox.unboxed_run(Repo, fn ->
        suffix = System.unique_integer([:positive])
        {:ok, user} = Identity.sync_user(%{"sub" => "commit-visibility-#{suffix}"}, %{})
        {:ok, room} = Rooms.create_room(%{"name" => "Commit visibility"}, user.id)

        {:ok, message} =
          Messages.create_message(
            %{"content" => "Commit antes do callback"},
            user.id,
            room.id,
            broadcaster: Chat.BroadcastCommitVisibilityStub
          )

        {user, room, message}
      end)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn -> Repo.delete(user) end)
    end)

    assert_receive {:broadcast_saw_committed_message, room_id, message_id, true}
    assert room_id == room.id
    assert message_id == message.id
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
    assert Messages.get_room_messages_count(room.id) == 1

    assert {:ok, repeated} =
             Messages.create_message(attrs, user.id, room.id, client_id: client_id)

    assert repeated.id == first.id
    assert repeated.client_id == client_id
    assert Messages.get_room_messages_count(room.id) == 1
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
end
