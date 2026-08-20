defmodule Chat.Messages.ReadReceipt do
  @moduledoc "Ecto schema for tracking message read receipts."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "read_receipts" do
    belongs_to :user, Chat.Accounts.User
    belongs_to :message, Chat.Messages.Message
    timestamps(type: :utc_datetime)
  end

  def changeset(read_receipt, attrs) do
    read_receipt
    |> cast(attrs, [:user_id, :message_id])
    |> validate_required([:user_id, :message_id])
    |> unique_constraint([:user_id, :message_id], name: :read_receipts_user_id_message_id_index)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:message_id)
  end
end
