defmodule Chat.Treatments.Treatment do
  @moduledoc "Ecto schema representing a Tratativa record."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "treatments" do
    field :protocol_number, :integer, read_after_writes: true
    field :order_id, :integer
    field :status, :string, default: "open"
    field :assigned_at, :utc_datetime_usec
    field :resolved_at, :utc_datetime_usec

    belongs_to :room, Chat.Rooms.Room
    belongs_to :opened_by, Chat.Accounts.User
    belongs_to :assigned_agent, Chat.Accounts.User
    belongs_to :resolved_by, Chat.Accounts.User
    has_many :audit_events, Chat.Treatments.AuditEvent

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(treatment, attrs) do
    treatment
    |> cast(attrs, [:order_id, :status, :room_id, :opened_by_id])
    |> validate_required([:order_id, :status, :room_id, :opened_by_id])
    |> validate_inclusion(:status, ["open", "in_progress", "resolved", "closed"])
    |> unique_constraint(:order_id)
    |> unique_constraint(:room_id)
  end

  def assignment_changeset(treatment, attrs) do
    treatment
    |> cast(attrs, [:assigned_agent_id, :assigned_at, :status])
    |> validate_required([:assigned_agent_id, :assigned_at])
    |> validate_inclusion(:status, ["open", "in_progress", "resolved", "closed"])
    |> foreign_key_constraint(:assigned_agent_id)
  end

  def unassignment_changeset(treatment) do
    change(treatment, %{status: "open", assigned_agent_id: nil, assigned_at: nil})
  end

  def resolution_changeset(treatment, resolved_by_id, resolved_at) do
    treatment
    |> change(%{status: "resolved", resolved_by_id: resolved_by_id, resolved_at: resolved_at})
    |> validate_required([:resolved_by_id, :resolved_at])
    |> foreign_key_constraint(:resolved_by_id)
  end

  def reopen_changeset(treatment) do
    change(treatment, %{status: "in_progress", resolved_by_id: nil, resolved_at: nil})
  end
end
