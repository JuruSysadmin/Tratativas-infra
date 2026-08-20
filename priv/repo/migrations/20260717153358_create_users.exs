defmodule Chat.Repo.Migrations.CreateUsers do
  @moduledoc "Database migration that creates the users table."

  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :username, :string, null: false
      add :password_hash, :string, null: false
      add :status, :string, default: "offline"
      timestamps()
    end

    create unique_index(:users, [:email])
    create unique_index(:users, [:username])
  end
end
