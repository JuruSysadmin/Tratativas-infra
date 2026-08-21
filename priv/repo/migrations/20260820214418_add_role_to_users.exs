defmodule Chat.Repo.Migrations.AddRoleToUsers do
  @moduledoc "Database migration that adds the operational role to users."

  use Ecto.Migration

  def change do
    alter table(:users) do
      add :role, :string, null: false, default: "commercial"
    end

    create constraint(:users, :users_role_check,
             check: "role IN ('commercial', 'logistics_agent')"
           )
  end
end
