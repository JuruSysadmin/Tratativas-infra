defmodule Chat.Repo.Migrations.AddExpiresAtToMessageAttachments do
  @moduledoc "Database migration that adds expiration timestamps to attachments."

  use Ecto.Migration

  def up do
    alter table(:message_attachments) do
      add :expires_at, :utc_datetime_usec
    end

    execute """
    UPDATE message_attachments
    SET expires_at = inserted_at + INTERVAL '5 minutes'
    WHERE expires_at IS NULL
    """

    alter table(:message_attachments) do
      modify :expires_at, :utc_datetime_usec, null: false
    end

    create index(:message_attachments, [:status, :expires_at])
  end

  def down do
    drop index(:message_attachments, [:status, :expires_at])

    alter table(:message_attachments) do
      remove :expires_at
    end
  end
end
