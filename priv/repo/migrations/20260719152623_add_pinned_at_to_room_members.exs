defmodule Chat.Repo.Migrations.AddPinnedAtToRoomMembers do
  use Ecto.Migration

  def change do
    alter table(:room_members) do
      add :pinned_at, :utc_datetime_usec
    end
  end
end
