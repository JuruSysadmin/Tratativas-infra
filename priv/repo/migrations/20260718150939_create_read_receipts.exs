defmodule Chat.Repo.Migrations.CreateReadReceipts do
  @moduledoc "Database migration that creates the message read receipts table."

  use Ecto.Migration

  def change do
    create table(:read_receipts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:read_receipts, [:user_id, :message_id])
    create index(:read_receipts, [:message_id])
    create index(:read_receipts, [:user_id])
  end
end
