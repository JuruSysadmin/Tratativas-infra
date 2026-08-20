defmodule Chat.Repo.Migrations.AddStatusToMessageAttachments do
  use Ecto.Migration

  def change do
    alter table(:message_attachments) do
      add :status, :string, null: false, default: "pending"
    end

    create index(:message_attachments, [:message_id, :status])

    create constraint(:message_attachments, :message_attachments_status_valid,
             check: "status IN ('pending', 'uploading', 'available', 'failed')"
           )
  end
end
