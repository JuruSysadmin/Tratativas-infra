defmodule Chat.Messages.MessageAttachment do
  @moduledoc "Persisted metadata for a file attached to a chat message."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "message_attachments" do
    field :storage_key, :string
    field :filename, :string
    field :content_type, :string
    field :size, :integer
    field :metadata, :map, default: %{}

    field :status, Ecto.Enum,
      values: [:pending, :uploading, :available, :failed],
      default: :pending

    field :expires_at, :utc_datetime_usec
    field :deleted_at, :utc_datetime_usec

    belongs_to :message, Chat.Messages.Message
    belongs_to :room, Chat.Rooms.Room
    belongs_to :uploaded_by, Chat.Accounts.User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [:storage_key, :filename, :content_type, :size, :metadata, :expires_at])
    |> validate_required([:storage_key, :filename, :content_type, :size])
    |> validate_length(:storage_key, max: 512)
    |> validate_length(:filename, max: 255)
    |> validate_length(:content_type, max: 255)
    |> validate_number(:size, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:message_id)
    |> check_constraint(:size, name: :message_attachments_size_non_negative)
    |> check_constraint(:status, name: :message_attachments_status_valid)
  end

  def reservation_changeset(attachment, attrs) do
    attachment
    |> changeset(attrs)
    |> cast(attrs, [:room_id, :uploaded_by_id])
    |> validate_required([:room_id, :uploaded_by_id])
  end
end
