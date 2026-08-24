defmodule Chat.Repo.Migrations.AddConfirmationFieldsToTreatments do
  use Ecto.Migration

  def up do
    alter table(:treatments) do
      add :closed_by_id, references(:users, type: :binary_id, on_delete: :restrict)
      add :closed_at, :utc_datetime_usec
    end

    create index(:treatments, [:closed_by_id])
  end

  def down do
    raise "This migration is irreversible because it stores treatment closure confirmation history"
  end
end
