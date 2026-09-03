defmodule Chat.Realtime.PayloadsTest do
  use ExUnit.Case, async: true

  alias Chat.Accounts.User
  alias Chat.Messages.{Message, MessageAttachment}
  alias Chat.Realtime.Payloads

  test "message payload includes the attachment download URL" do
    attachment = %MessageAttachment{
      id: Ecto.UUID.generate(),
      storage_key: "message-attachments/room/attachment.png",
      filename: "attachment.png",
      content_type: "image/png",
      size: 128
    }

    message = %Message{
      id: Ecto.UUID.generate(),
      client_id: Ecto.UUID.generate(),
      content: "",
      user: %User{id: Ecto.UUID.generate(), username: "usuario"},
      attachments: [attachment]
    }

    assert %{attachments: [%{download_url: "https://storage.test/download/" <> path}]} =
             Payloads.message(message,
               presigner: Chat.TestSupport.MessageAttachmentPresigner
             )

    assert path == attachment.storage_key
  end

  test "message payload serializes naive timestamps as explicit UTC" do
    message = %Message{
      id: Ecto.UUID.generate(),
      user: %User{id: Ecto.UUID.generate(), username: "usuario"},
      inserted_at: ~N[2026-09-01 02:30:00.123456],
      edited_at: nil,
      attachments: []
    }

    assert %{inserted_at: "2026-09-01T02:30:00.123456Z", edited_at: nil} =
             Payloads.message(message)
  end
end
