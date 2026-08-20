defmodule Chat.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @moduledoc """
  Schema de usuario do chat.

  Campos de integracao ERP/legado:
  - matricula: Codigo do funcionario na pcempr (ex: "M12345")
  - codusur: Codigo rca na pcusuari (ex: "RCA")
  - filial: Codigo da filial (ex: "1", "2")
  """

  schema "users" do
    field :email, :string
    field :username, :string
    field :password_hash, :string
    field :status, :string, default: "offline"
    field :matricula, :string
    field :codusur, :string
    field :filial, :string
    field :auth_provider, :string, default: "local"
    field :auth_subject, :string

    has_many :messages, Chat.Messages.Message
    has_many :created_rooms, Chat.Rooms.Room, foreign_key: :creator_id
    many_to_many :rooms, Chat.Rooms.Room, join_through: "room_members"

    timestamps()
  end

  @doc """
  Changeset para autenticacao e criacao de conta.
  """
  def auth_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :email,
      :username,
      :matricula,
      :codusur,
      :filial,
      :auth_provider,
      :auth_subject
    ])
    |> validate_required([:email, :username])
    |> unique_constraint(:email)
    |> unique_constraint(:username)
    |> unique_constraint(:matricula)
  end

  def external_auth_changeset(user, attrs) do
    user
    |> auth_changeset(attrs)
    |> validate_required([:auth_provider, :auth_subject])
    |> unique_constraint([:auth_provider, :auth_subject])
  end

  @doc """
  Changeset para atualizacao de status (online/offline/away).
  """

  def status_changeset(user, attrs) do
    user
    |> cast(attrs, [:status])
    |> validate_inclusion(:status, ["online", "offline", "away"])
  end
end
