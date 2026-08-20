defmodule Chat.Repo.Migrations.AddAttachmentReservationOwnership do
  @moduledoc "Database migration that adds attachment reservation ownership."

  use Ecto.Migration

  def up do
    alter table(:message_attachments) do
      modify :message_id, :binary_id, null: true
      add :room_id, references(:rooms, type: :binary_id, on_delete: :delete_all), null: true

      add :uploaded_by_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: true
    end

    execute """
    UPDATE message_attachments AS attachment
    SET room_id = message.room_id,
        uploaded_by_id = message.user_id
    FROM messages AS message
    WHERE attachment.message_id = message.id
    """

    alter table(:message_attachments) do
      modify :room_id, :binary_id, null: false
      modify :uploaded_by_id, :binary_id, null: false
    end

    create index(:message_attachments, [:room_id, :uploaded_by_id, :status])
  end

  def down do
    drop index(:message_attachments, [:room_id, :uploaded_by_id, :status])

    alter table(:message_attachments) do
      remove :room_id
      remove :uploaded_by_id
      modify :message_id, :binary_id, null: false
    end
  end
end
