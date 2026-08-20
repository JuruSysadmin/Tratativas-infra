defmodule Chat.Messages.AttachmentsTest do
  use Chat.DataCase, async: false

  import Ecto.Query

  alias Chat.Auth.Identity
  alias Chat.Messages
  alias Chat.Messages.{Attachments, MessageAttachment}
  alias Chat.Repo
  alias Chat.Rooms
  alias Chat.Workers.VerifyMessageAttachment

  setup do
    {:ok, owner} = Identity.sync_user(%{"sub" => "attachment-owner"}, %{})
    {:ok, outsider} = Identity.sync_user(%{"sub" => "attachment-outsider"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Attachments"}, owner.id)
    %{owner: owner, outsider: outsider, room: room}
  end

  test "reserves an authorized attachment with a presigned upload URL", %{
    owner: owner,
    room: room
  } do
    assert {:ok, attachment, upload_url} =
             Attachments.presign_upload(
               owner.id,
               room.id,
               %{
                 "filename" => "../documento.pdf",
                 "content_type" => "application/pdf",
                 "size" => 128
               },
               presigner: Chat.TestSupport.MessageAttachmentPresigner
             )

    assert attachment.status == :pending
    assert DateTime.diff(attachment.expires_at, DateTime.utc_now(), :second) in 295..300
    assert attachment.filename == "documento.pdf"
    assert attachment.storage_key =~ "message-attachments/#{room.id}/#{attachment.id}.pdf"
    assert upload_url =~ attachment.storage_key
    assert Repo.get!(MessageAttachment, attachment.id).status == :pending

    assert [job] =
             Repo.all(
               from job in Oban.Job,
                 where: job.worker == "Chat.Workers.VerifyMessageAttachment",
                 select: job
             )

    assert job.args == %{"attachment_id" => attachment.id}
    assert job.state == "scheduled"
    assert DateTime.diff(job.scheduled_at, job.inserted_at, :second) >= 30
  end

  test "builds a download payload with a presigned URL", %{owner: owner, room: room} do
    assert {:ok, attachment, _upload_url} =
             Attachments.presign_upload(
               owner.id,
               room.id,
               %{"filename" => "foto.png", "content_type" => "image/png", "size" => 128},
               presigner: Chat.TestSupport.MessageAttachmentPresigner
             )

    assert %{
             id: id,
             filename: "foto.png",
             content_type: "image/png",
             size: 128,
             download_url: "https://storage.test/download/" <> _
           } =
             Attachments.payload(attachment,
               presigner: Chat.TestSupport.MessageAttachmentPresigner
             )

    assert id == attachment.id
  end

  test "rejects a user who is not a room member", %{
    outsider: outsider,
    room: room
  } do
    assert {:error, :not_found} =
             Attachments.presign_upload(
               outsider.id,
               room.id,
               %{
                 "filename" => "documento.pdf",
                 "content_type" => "application/pdf",
                 "size" => 128
               },
               presigner: Chat.TestSupport.MessageAttachmentPresigner
             )
  end

  test "rejects unsupported types and files larger than 10 MB", %{
    owner: owner,
    room: room
  } do
    assert {:error, :unsupported_content_type} =
             Attachments.presign_upload(
               owner.id,
               room.id,
               %{
                 "filename" => "script.exe",
                 "content_type" => "application/octet-stream",
                 "size" => 128
               },
               presigner: Chat.TestSupport.MessageAttachmentPresigner
             )

    assert {:error, :file_too_large} =
             Attachments.presign_upload(
               owner.id,
               room.id,
               %{
                 "filename" => "large.pdf",
                 "content_type" => "application/pdf",
                 "size" => 10_485_761
               },
               presigner: Chat.TestSupport.MessageAttachmentPresigner
             )
  end

  test "confirms idempotently when Oban already made the attachment available", %{
    owner: owner,
    room: room
  } do
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

    attachment_id = attachment.id

    assert {:ok, %{id: ^attachment_id, status: :available}} =
             Attachments.confirm_upload(owner.id, room.id, attachment.id)
  end

  test "rejects confirmation after the attachment reservation expires", %{
    owner: owner,
    room: room
  } do
    assert {:ok, attachment, _upload_url} =
             Attachments.presign_upload(
               owner.id,
               room.id,
               %{
                 "filename" => "expirada.pdf",
                 "content_type" => "application/pdf",
                 "size" => 128
               },
               presigner: Chat.TestSupport.MessageAttachmentPresigner
             )

    expired_at = DateTime.add(DateTime.utc_now(), -1, :second)

    Repo.update_all(
      from(item in MessageAttachment, where: item.id == ^attachment.id),
      set: [expires_at: expired_at]
    )

    assert {:error, :expired} = Attachments.confirm_upload(owner.id, room.id, attachment.id)
  end

  test "persists a message containing only an attachment", %{owner: owner, room: room} do
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

    assert {:ok, %{content: ""} = message} =
             Messages.create_message(
               %{"content" => ""},
               owner.id,
               room.id,
               client_id: Ecto.UUID.generate(),
               attachment_ids: [attachment.id],
               broadcaster: Chat.BroadcastFailureStub
             )

    assert Repo.get!(MessageAttachment, attachment.id).message_id == message.id
  end

  test "worker accepts an available attachment after it is linked to a message", %{
    owner: owner,
    room: room
  } do
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

    assert {:ok, %{content: ""}} =
             Messages.create_message(
               %{"content" => ""},
               owner.id,
               room.id,
               client_id: Ecto.UUID.generate(),
               attachment_ids: [attachment.id],
               broadcaster: Chat.BroadcastFailureStub
             )

    assert :ok =
             VerifyMessageAttachment.perform(%Oban.Job{
               args: %{"attachment_id" => attachment.id}
             })
  end

  test "marks orphaned attachments older than 24 hours as deleted", %{owner: owner, room: room} do
    assert {:ok, attachment, _upload_url} =
             Attachments.presign_upload(
               owner.id,
               room.id,
               %{
                 "filename" => "expirada.pdf",
                 "content_type" => "application/pdf",
                 "size" => 128
               },
               presigner: Chat.TestSupport.MessageAttachmentPresigner
             )

    old_inserted_at = DateTime.add(DateTime.utc_now(), -25 * 60 * 60, :second)

    Repo.update_all(from(item in MessageAttachment, where: item.id == ^attachment.id),
      set: [inserted_at: old_inserted_at]
    )

    assert {:ok, 1} =
             Attachments.cleanup_orphaned(
               older_than: DateTime.add(DateTime.utc_now(), -24 * 60 * 60, :second),
               deleter: Chat.TestSupport.MessageAttachmentDeleter
             )

    assert %{deleted_at: deleted_at} = Repo.get!(MessageAttachment, attachment.id)
    assert not is_nil(deleted_at)
  end
end
