defmodule Chat.Repo.Migrations.AddUniqueRoomNameIndex do
  use Ecto.Migration

  def up do
    execute("""
    WITH ranked_rooms AS (
      SELECT id, ROW_NUMBER() OVER (PARTITION BY name ORDER BY inserted_at ASC, id ASC) AS position
      FROM rooms
    )
    DELETE FROM rooms
    USING ranked_rooms
    WHERE rooms.id = ranked_rooms.id AND ranked_rooms.position > 1
    """)

    create unique_index(:rooms, [:name])
  end

  def down do
    drop unique_index(:rooms, [:name])
  end
end
