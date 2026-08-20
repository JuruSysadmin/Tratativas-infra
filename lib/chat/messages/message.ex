defmodule Chat.Messages.Message do
  @moduledoc "Ecto schema and changeset functions for chat messages."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "messages" do
    field :content, :string
    field :client_id, :binary_id
    field :deleted_at, :utc_datetime_usec
    field :edited_at, :utc_datetime_usec
    field :read_count, :integer, virtual: true, default: 0
    field :delivered_count, :integer, virtual: true, default: 0
    field :reader_names, {:array, :string}, virtual: true, default: []

    belongs_to :user, Chat.Accounts.User
    belongs_to :room, Chat.Rooms.Room
    has_many :mentions, Chat.Messages.Mention
    has_many :attachments, Chat.Messages.MessageAttachment
    has_many :revisions, Chat.Messages.MessageRevision

    timestamps(type: :naive_datetime_usec)
  end

  def changeset(message, attrs, opts \\ []) do
    allow_empty_content = Keyword.get(opts, :allow_empty_content, false)

    message
    |> cast_content(attrs, allow_empty_content)
    |> validate_content(allow_empty_content)
    |> unique_constraint(:client_id)
  end

  defp cast_content(message, attrs, true), do: cast(message, attrs, [:content], empty_values: [])
  defp cast_content(message, attrs, false), do: cast(message, attrs, [:content])

  defp validate_content(changeset, true), do: validate_length(changeset, :content, max: 4000)

  defp validate_content(changeset, false) do
    changeset
    |> validate_required([:content])
    |> validate_length(:content, min: 1, max: 4000)
  end
end
