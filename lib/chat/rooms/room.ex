defmodule Chat.Rooms.Room do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "rooms" do
    field :name, :string
    field :description, :string
    field :order_id, :integer
    field :pinned_at, :utc_datetime_usec, virtual: true
    field :last_message_preview, :string, virtual: true

    belongs_to :creator, Chat.Accounts.User
    has_many :messages, Chat.Messages.Message
    many_to_many :members, Chat.Accounts.User, join_through: "room_members"

    timestamps()
  end

  def changeset(room, attrs) do
    room
    |> cast(attrs, [:name, :description, :order_id])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 50)
    |> unique_constraint(:name)
    |> unique_constraint(:order_id, name: :rooms_order_id_index)
  end
end
