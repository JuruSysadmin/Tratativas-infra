defmodule Chat.Repo.Migrations.AddPaginationIndexToTreatments do
  @moduledoc "Adds composite index for cursor pagination on treatments."

  use Ecto.Migration

  def change do
    create index(:treatments, [:inserted_at, :id])
  end
end
