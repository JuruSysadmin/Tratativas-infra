defmodule Chat.Messages.MessageRevision do
  @moduledoc "Immutable snapshot of a message before an edit."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "message_revisions" do
    field :content, :string

    belongs_to :message, Chat.Messages.Message
    belongs_to :editor, Chat.Accounts.User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(revision, attrs) do
    revision
    |> cast(attrs, [:content])
    |> validate_required([:content])
    |> validate_length(:content, min: 1, max: 4000)
    |> foreign_key_constraint(:message_id)
    |> foreign_key_constraint(:editor_id)
  end
end
