defmodule Chat.Treatments.Treatment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "treatments" do
    field :protocol_number, :integer, read_after_writes: true
    field :order_id, :integer
    field :status, :string, default: "open"

    belongs_to :room, Chat.Rooms.Room
    belongs_to :opened_by, Chat.Accounts.User
    has_many :audit_events, Chat.Treatments.AuditEvent

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(treatment, attrs) do
    treatment
    |> cast(attrs, [:order_id, :status, :room_id, :opened_by_id])
    |> validate_required([:order_id, :status, :room_id, :opened_by_id])
    |> validate_inclusion(:status, ["open", "closed"])
    |> unique_constraint(:order_id)
    |> unique_constraint(:room_id)
  end
end
