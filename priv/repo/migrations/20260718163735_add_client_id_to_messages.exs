defmodule Chat.Repo.Migrations.AddClientIdToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :client_id, :binary_id
    end

    create unique_index(:messages, [:client_id], where: "client_id IS NOT NULL")
  end
end
