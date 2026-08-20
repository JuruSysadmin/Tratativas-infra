defmodule Chat.Repo.Migrations.CreateMessageAttachments do
  @moduledoc "Database migration that creates the message attachments table."

  use Ecto.Migration

  def change do
    create table(:message_attachments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      add :storage_key, :string, null: false
      add :filename, :string, null: false
      add :content_type, :string, null: false
      add :size, :bigint, null: false
      add :metadata, :map, null: false, default: %{}
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:message_attachments, [:message_id])
    create index(:message_attachments, [:storage_key])

    create constraint(:message_attachments, :message_attachments_size_non_negative,
             check: "size >= 0"
           )
  end
end
