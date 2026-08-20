defmodule Chat.Repo.Migrations.AddOrderIdToRooms do
  @moduledoc "Database migration that associates rooms with orders."

  use Ecto.Migration

  def change do
    alter table(:rooms) do
      add :order_id, :bigint
    end

    create unique_index(:rooms, [:order_id], where: "order_id IS NOT NULL")
  end
end
