defmodule Chat.Messages.Mention do
  @moduledoc "Persisted occurrence of a room-member mention in a message."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "message_mentions" do
    field :username_snapshot, :string
    field :start_offset, :integer
    field :length, :integer

    belongs_to :message, Chat.Messages.Message
    belongs_to :mentioned_user, Chat.Accounts.User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(mention, attrs) do
    mention
    |> cast(attrs, [:username_snapshot, :start_offset, :length])
    |> validate_required([:username_snapshot, :start_offset, :length])
    |> validate_number(:start_offset, greater_than_or_equal_to: 0)
    |> validate_number(:length, greater_than: 0)
    |> foreign_key_constraint(:message_id)
    |> foreign_key_constraint(:mentioned_user_id)
    |> unique_constraint([:message_id, :mentioned_user_id, :start_offset],
      name: :message_mentions_occurrence_index
    )
  end
end
