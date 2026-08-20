defmodule Chat.Repo.Migrations.CreateRoomDeliveryPositions do
  @moduledoc "Database migration that creates the room delivery positions table."

  use Ecto.Migration

  def change do
    create table(:room_delivery_positions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :room_id, references(:rooms, type: :binary_id, on_delete: :delete_all), null: false

      add :last_delivered_message_id, :binary_id, null: false
      add :last_delivered_message_inserted_at, :naive_datetime_usec, null: false
      add :last_delivered_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:room_delivery_positions, [:user_id, :room_id])
    create index(:room_delivery_positions, [:room_id])
  end
end
