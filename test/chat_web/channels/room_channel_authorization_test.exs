defmodule ChatWeb.RoomChannelAuthorizationTest do
  use Chat.DataCase, async: true

  import Phoenix.ChannelTest

  alias Chat.Auth.Identity
  alias Chat.Messages
  alias Chat.Messages.{Attachments, MessageAttachment}
  alias Chat.Repo
  alias Chat.Rooms
  alias ChatWeb.RoomChannel
  alias ChatWeb.UserSocket

  @endpoint ChatWeb.Endpoint

  test "cannot delete a message from another room through the current room channel" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-owner"}, %{})
    {:ok, current_room} = Rooms.create_room(%{"name" => "Sala atual"}, owner.id)
    {:ok, other_room} = Rooms.create_room(%{"name" => "Outra sala"}, owner.id)

    {:ok, other_message} =
      Messages.create_message(%{"content" => "Mensagem isolada"}, owner.id, other_room.id)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-owner", %{current_user: owner})
      |> subscribe_and_join(RoomChannel, "room:#{current_room.id}")

    ref = push(socket, "message:delete", %{"message_id" => other_message.id})

    assert_reply ref, :error, %{reason: "not_found"}
    assert Messages.get_message(other_message.id)
  end

  test "rejects a room rejoin after the user's membership is revoked" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "rejoin-owner"}, %{})
    {:ok, member} = Identity.sync_user(%{"sub" => "rejoin-member"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Sala de reentrada"}, owner.id)
    assert {:ok, _membership} = Rooms.join_room(member.id, room.id)

    {:ok, _reply, _socket} =
      UserSocket
      |> socket("rejoin-member", %{current_user: member})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    assert {:ok, 1} = Rooms.leave_room(member.id, room.id)

    assert {:error, %{reason: "unauthorized"}} =
             UserSocket
             |> socket("rejoin-member-after-revocation", %{current_user: member})
             |> subscribe_and_join(RoomChannel, "room:#{room.id}")
  end

  test "cannot delete a message already read by another room member" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-read-owner"}, %{})
    {:ok, reader} = Identity.sync_user(%{"sub" => "channel-reader"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Sala com leitura"}, owner.id)
    assert {:ok, _membership} = Rooms.join_room(reader.id, room.id)

    assert {:ok, message} =
             Messages.create_message(%{"content" => "Mensagem lida"}, owner.id, room.id)

    assert :ok = Messages.mark_as_read(message.id, reader.id)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-read-owner", %{current_user: owner})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref = push(socket, "message:delete", %{"message_id" => message.id})

    assert_reply ref, :error, %{reason: "already_read"}
    assert Messages.get_message(message.id)
  end

  test "author can delete an unread message without crashing the channel" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-delete-owner"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Sala para excluir"}, owner.id)

    assert {:ok, message} =
             Messages.create_message(%{"content" => "Mensagem removível"}, owner.id, room.id)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-delete-owner", %{current_user: owner})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    channel_pid = socket.channel_pid
    channel_ref = Process.monitor(channel_pid)
    ref = push(socket, "message:delete", %{"message_id" => message.id})

    assert_reply ref, :ok
    refute_receive {:DOWN, ^channel_ref, :process, ^channel_pid, _reason}
    assert Messages.get_message(message.id) == nil
  end

  test "creating a message pushes it once and keeps the channel alive" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-create-owner"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Sala para criar"}, owner.id)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-create-owner", %{current_user: owner})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    channel_pid = socket.channel_pid
    channel_ref = Process.monitor(channel_pid)
    client_id = Ecto.UUID.generate()
    ref = push(socket, "message:new", %{"content" => "Mensagem nova", "client_id" => client_id})

    assert_reply ref, :ok

    assert_push "message:new", %{
      content: "Mensagem nova",
      room_id: room_id
    }

    assert room_id == room.id
    assert Messages.list_messages(room.id) |> length() == 1
    refute_push "message:new", _duplicate
    refute_receive {:DOWN, ^channel_ref, :process, ^channel_pid, _reason}

    delete_ref =
      push(socket, "message:delete", %{
        "message_id" => List.first(Messages.list_messages(room.id)).id
      })

    assert_reply delete_ref, :ok
  end

  test "creates an attachment-only message through the channel" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-attachment-owner"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Sala com anexo"}, owner.id)

    assert {:ok, attachment, _upload_url} =
             Attachments.presign_upload(
               owner.id,
               room.id,
               %{
                 "filename" => "documento.pdf",
                 "content_type" => "application/pdf",
                 "size" => 128
               },
               presigner: Chat.TestSupport.MessageAttachmentPresigner
             )

    attachment
    |> Ecto.Changeset.change(status: :available)
    |> Repo.update!()

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-attachment-owner", %{current_user: owner})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref =
      push(socket, "message:new", %{
        "content" => "",
        "client_id" => Ecto.UUID.generate(),
        "attachment_ids" => [attachment.id]
      })

    assert_reply ref, :ok

    assert_receive {:message_created, %{content: "", attachments: [%{id: attachment_id}]}}
    assert attachment_id == attachment.id
    assert [%{content: ""}] = Messages.list_messages(room.id)
    assert Repo.get!(MessageAttachment, attachment.id).message_id != nil
  end

  test "reusing a client id does not create or broadcast a duplicate message" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-idempotent-owner"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Sala idempotente"}, owner.id)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-idempotent-owner", %{current_user: owner})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    client_id = Ecto.UUID.generate()
    payload = %{"content" => "Mensagem idempotente", "client_id" => client_id}

    first_ref = push(socket, "message:new", payload)
    assert_reply first_ref, :ok
    assert_push "message:new", %{content: "Mensagem idempotente"}

    second_ref = push(socket, "message:new", payload)
    assert_reply second_ref, :ok
    refute_push "message:new", _duplicate
    assert [%{content: "Mensagem idempotente"}] = Messages.list_messages(room.id)
  end

  test "rejects malformed message payloads without terminating the channel" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-invalid-owner"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Sala inválida"}, owner.id)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-invalid-owner", %{current_user: owner})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    channel_pid = socket.channel_pid
    channel_ref = Process.monitor(channel_pid)
    ref = push(socket, "message:new", %{"content" => []})

    assert_reply ref, :error, %{reason: "invalid_message"}
    refute_receive {:DOWN, ^channel_ref, :process, ^channel_pid, _reason}
  end

  test "read receipt updates are pushed without crashing the channel" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-receipt-owner"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Sala com recibos"}, owner.id)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-receipt-owner", %{current_user: owner})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    channel_pid = socket.channel_pid
    channel_ref = Process.monitor(channel_pid)
    message_ids = [Ecto.UUID.generate()]

    assert :ok =
             Chat.Broadcaster.broadcast_read_receipts_updated(room.id, owner.id, message_ids)

    assert_push "read_receipts:updated", %{
      user_id: user_id,
      message_ids: ^message_ids
    }

    assert user_id == owner.id
    refute_receive {:DOWN, ^channel_ref, :process, ^channel_pid, _reason}
  end
end
