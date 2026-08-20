defmodule Chat.Messages.MessageAttachmentTest do
  use Chat.DataCase, async: true

  alias Chat.Messages.MessageAttachment

  test "builds an attachment changeset with metadata default" do
    changeset =
      MessageAttachment.changeset(%MessageAttachment{}, %{
        storage_key: "rooms/room-1/messages/message-1/documento.pdf",
        filename: "documento.pdf",
        content_type: "application/pdf",
        size: 128
      })

    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :metadata) == %{}
  end

  test "requires storage metadata and a non-negative size" do
    changeset =
      MessageAttachment.changeset(%MessageAttachment{}, %{
        storage_key: "",
        filename: "",
        content_type: "",
        size: -1
      })

    refute changeset.valid?
    assert errors_on(changeset).storage_key == ["can't be blank"]
    assert errors_on(changeset).filename == ["can't be blank"]
    assert errors_on(changeset).content_type == ["can't be blank"]
    assert errors_on(changeset).size == ["must be greater than or equal to 0"]
  end
end
