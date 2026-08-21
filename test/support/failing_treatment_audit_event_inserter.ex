defmodule Chat.TestSupport.FailingTreatmentAuditEventInserter do
  @moduledoc false

  import Ecto.Changeset

  def insert(changeset) do
    {:error, add_error(changeset, :event_type, "forced audit failure")}
  end
end
