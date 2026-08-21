defmodule Chat.Repo.Migrations.AddAssignmentFieldsToTreatments do
  use Ecto.Migration

  def change do
    alter table(:treatments) do
      add :assigned_agent_id,
          references(:users, type: :binary_id, on_delete: :nilify_all)

      add :assigned_at, :utc_datetime_usec
    end

    create index(:treatments, [:assigned_agent_id])
  end
end
