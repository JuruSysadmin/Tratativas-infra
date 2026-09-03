defmodule Chat.Repo.Migrations.AddSlaPausedSecondsToTreatments do
  use Ecto.Migration

  def change do
    alter table(:treatments) do
      add :sla_paused_seconds, :integer, null: false, default: 0
    end

    create constraint(:treatments, :sla_paused_seconds_non_negative,
             check: "sla_paused_seconds >= 0"
           )
  end
end
