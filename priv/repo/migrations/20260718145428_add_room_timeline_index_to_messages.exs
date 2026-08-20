defmodule Chat.Repo.Migrations.AddRoomTimelineIndexToMessages do
  use Ecto.Migration

  def change do
    drop_if_exists index(:messages, [:room_id, :inserted_at])
    create index(:messages, [:room_id, :inserted_at, :id])
  end
end
