defmodule Chat.Repo.Migrations.CreateRooms do
  use Ecto.Migration

  def change do
    create table(:rooms, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :string
      add :creator_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      timestamps()
    end

    create index(:rooms, [:creator_id])
  end
end
