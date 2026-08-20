defmodule Chat.Messages.RoomReadPosition do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "room_read_positions" do
    field :user_id, :binary_id
    field :room_id, :binary_id
    field :last_read_message_id, :binary_id
    field :last_read_message_inserted_at, :naive_datetime_usec
    field :last_read_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end
end
