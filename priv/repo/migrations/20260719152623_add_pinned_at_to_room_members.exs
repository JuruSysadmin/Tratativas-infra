defmodule Chat.Repo.Migrations.AddPinnedAtToRoomMembers do
  @moduledoc "Database migration that adds room member pinning timestamps."

  use Ecto.Migration

  def change do
    alter table(:room_members) do
      add :pinned_at, :utc_datetime_usec
    end
  end
end
