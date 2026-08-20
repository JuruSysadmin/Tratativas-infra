defmodule Chat.Repo.Migrations.CreateMessageRevisions do
  use Ecto.Migration

  def change do
    create table(:message_revisions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :content, :text, null: false

      add :message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      add :editor_id, references(:users, type: :binary_id, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:message_revisions, [:message_id, :inserted_at])
  end
end
