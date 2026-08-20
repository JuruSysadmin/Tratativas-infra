defmodule Chat.Repo.Migrations.IncreaseMessageTimestampsPrecision do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      modify :inserted_at, :naive_datetime_usec, from: :naive_datetime
      modify :updated_at, :naive_datetime_usec, from: :naive_datetime
    end
  end
end
