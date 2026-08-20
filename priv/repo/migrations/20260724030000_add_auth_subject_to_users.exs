defmodule Chat.Repo.Migrations.AddAuthSubjectToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :auth_subject, :string
    end

    create unique_index(:users, [:auth_provider, :auth_subject])
  end
end
