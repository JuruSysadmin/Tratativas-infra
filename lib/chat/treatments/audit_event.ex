defmodule Chat.Treatments.AuditEvent do
  @moduledoc "Ecto schema for immutable Tratativa audit events."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "treatment_audit_events" do
    field :event_type, :string
    field :metadata, :map, default: %{}

    belongs_to :treatment, Chat.Treatments.Treatment
    belongs_to :actor, Chat.Accounts.User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:event_type, :metadata, :treatment_id, :actor_id])
    |> validate_required([:event_type, :treatment_id, :actor_id])
    |> validate_length(:event_type, min: 1, max: 100)
  end
end
