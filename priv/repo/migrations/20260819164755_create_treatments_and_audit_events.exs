defmodule Chat.Repo.Migrations.CreateTreatmentsAndAuditEvents do
  use Ecto.Migration

  def change do
    create table(:treatments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :protocol_number, :bigserial, null: false
      add :order_id, :bigint, null: false
      add :status, :string, null: false, default: "open"
      add :room_id, references(:rooms, type: :binary_id, on_delete: :restrict), null: false
      add :opened_by_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:treatments, [:protocol_number])
    create unique_index(:treatments, [:order_id])
    create unique_index(:treatments, [:room_id])
    create index(:treatments, [:status])

    create table(:treatment_audit_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_type, :string, null: false
      add :metadata, :map, null: false, default: %{}

      add :treatment_id, references(:treatments, type: :binary_id, on_delete: :restrict),
        null: false

      add :actor_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:treatment_audit_events, [:treatment_id, :inserted_at])
    create index(:treatment_audit_events, [:actor_id])
  end
end
