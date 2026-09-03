defmodule Chat.Repo.Migrations.MigrateResolvedTreatmentsToPendingConfirmation do
  use Ecto.Migration

  def change do
    execute(
      "UPDATE treatments SET status = 'pending_confirmation' WHERE status = 'resolved'",
      "UPDATE treatments SET status = 'resolved' WHERE status = 'pending_confirmation'"
    )
  end
end
