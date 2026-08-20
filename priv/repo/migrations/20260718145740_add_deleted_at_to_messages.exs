defmodule Chat.Repo.Migrations.AddDeletedAtToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :deleted_at, :utc_datetime_usec
    end

    drop_if_exists index(:messages, [:room_id, :inserted_at, :id])

    create index(:messages, [:room_id, :inserted_at, :id], where: "deleted_at IS NULL")
  end
end
