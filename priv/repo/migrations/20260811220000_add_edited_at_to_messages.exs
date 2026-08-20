defmodule Chat.Repo.Migrations.AddEditedAtToMessages do
  @moduledoc "Database migration that adds edit timestamps to messages."

  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :edited_at, :utc_datetime_usec
    end
  end
end
