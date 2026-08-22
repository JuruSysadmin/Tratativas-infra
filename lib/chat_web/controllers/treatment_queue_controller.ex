defmodule ChatWeb.TreatmentQueueController do
  @moduledoc "HTTP endpoints for the treatment queue list."

  use ChatWeb, :controller

  alias Chat.Treatments

  def index(conn, _params) do
    user = conn.assigns.current_user
    treatments = Treatments.list_queue(user)

    items =
      Enum.map(treatments, fn t ->
        %{
          room_id: t.room_id,
          order_id: t.order_id,
          treatment_id: t.id,
          protocol: Treatments.protocol(t),
          status: t.status,
          assigned_agent_id: t.assigned_agent_id,
          assigned_agent_name: if(t.assigned_agent, do: t.assigned_agent.username, else: nil)
        }
      end)

    json(conn, %{items: items})
  end
end
