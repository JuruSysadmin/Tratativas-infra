defmodule Chat.Repo.Migrations.AddAuthFieldsToUsers do
  @moduledoc "Database migration that adds authentication fields to users."

  use Ecto.Migration

  def change do
    alter table(:users) do
      add :matricula, :string
      add :codusur, :string
      add :filial, :string
      add :auth_provider, :string, default: "local"
    end

    create unique_index(:users, [:matricula])
  end
end
