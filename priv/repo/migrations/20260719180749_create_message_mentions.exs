defmodule Chat.Repo.Migrations.CreateMessageMentions do
  use Ecto.Migration

  def change do
    create table(:message_mentions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      add :mentioned_user_id, references(:users, type: :binary_id, on_delete: :nothing),
        null: false

      add :username_snapshot, :string, null: false
      add :start_offset, :integer, null: false
      add :length, :integer, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:message_mentions, [:message_id])
    create index(:message_mentions, [:mentioned_user_id, :inserted_at])

    create unique_index(
             :message_mentions,
             [:message_id, :mentioned_user_id, :start_offset],
             name: :message_mentions_occurrence_index
           )

    create constraint(:message_mentions, :message_mentions_start_offset_non_negative,
             check: "start_offset >= 0"
           )

    create constraint(:message_mentions, :message_mentions_length_positive, check: "length > 0")
  end
end
