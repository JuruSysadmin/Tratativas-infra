defmodule Chat.Repo.Migrations.AddResolutionFieldsToTreatments do
  use Ecto.Migration

  def up do
    alter table(:treatments) do
      add :resolved_by_id,
          references(:users, type: :binary_id, on_delete: :restrict)

      add :resolved_at, :utc_datetime_usec
    end

    create index(:treatments, [:resolved_by_id])
  end

  def down do
    raise "This migration is irreversible because it stores treatment resolution history"
  end
end
