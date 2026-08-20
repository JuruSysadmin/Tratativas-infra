defmodule Chat.Repo.Migrations.MakePasswordHashNullable do
  @moduledoc "Database migration that makes the user password hash nullable."

  use Ecto.Migration

  def change do
    alter table(:users) do
      modify :password_hash, :string, null: true
    end
  end
end
