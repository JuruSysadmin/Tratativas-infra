defmodule Chat.Repo.Migrations.CreateRoomReadPositions do
  use Ecto.Migration

  def change do
    create table(:room_read_positions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :room_id, references(:rooms, type: :binary_id, on_delete: :delete_all), null: false

      add :last_read_message_id, :binary_id, null: false
      add :last_read_message_inserted_at, :naive_datetime_usec, null: false
      add :last_read_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:room_read_positions, [:user_id, :room_id])
    create index(:room_read_positions, [:room_id])

    execute(
      """
      INSERT INTO room_read_positions (
        id,
        user_id,
        room_id,
        last_read_message_id,
        last_read_message_inserted_at,
        last_read_at,
        inserted_at,
        updated_at
      )
      SELECT
        gen_random_uuid(),
        latest.user_id,
        latest.room_id,
        latest.message_id,
        latest.message_inserted_at,
        latest.receipt_updated_at AT TIME ZONE 'UTC',
        NOW(),
        NOW()
      FROM (
        SELECT DISTINCT ON (receipt.user_id, message.room_id)
          receipt.user_id,
          message.room_id,
          message.id AS message_id,
          message.inserted_at AS message_inserted_at,
          receipt.updated_at AS receipt_updated_at
        FROM read_receipts AS receipt
        INNER JOIN messages AS message ON message.id = receipt.message_id
        ORDER BY receipt.user_id, message.room_id, message.inserted_at DESC, message.id DESC
      ) AS latest
      """,
      "SELECT 1"
    )
  end
end
