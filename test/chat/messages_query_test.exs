defmodule Chat.MessagesQueryTest do
  use Chat.DataCase, async: false

  alias Chat.Auth.Identity
  alias Chat.Messages
  alias Chat.Rooms

  setup do
    {:ok, user} = Identity.sync_user(%{"sub" => "message-user"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Mensagens"}, user.id)

    Phoenix.PubSub.subscribe(Chat.PubSub, "room:#{room.id}")

    %{user: user, room: room}
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
end
