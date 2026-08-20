defmodule Chat.Rooms.RoomMember do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "room_members" do
    field :pinned_at, :utc_datetime_usec

    belongs_to :user, Chat.Accounts.User
    belongs_to :room, Chat.Rooms.Room
  end

  def changeset(room_member, attrs) do
    room_member
    |> cast(attrs, [:user_id, :room_id])
    |> validate_required([:user_id, :room_id])
    |> unique_constraint([:user_id, :room_id])
  end
end
