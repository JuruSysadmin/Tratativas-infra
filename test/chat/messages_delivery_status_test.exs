defmodule Chat.MessagesDeliveryStatusTest do
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
end
