defmodule Chat.Repo.Migrations.AddOban do
  @moduledoc "Database migration that adds Oban job storage."

  use Ecto.Migration

  def up, do: Oban.Migrations.up()

  def down, do: Oban.Migrations.down()
end
