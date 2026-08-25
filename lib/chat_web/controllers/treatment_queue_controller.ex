defmodule ChatWeb.TreatmentQueueController do
  @moduledoc "HTTP endpoints for the treatment queue list."

  use ChatWeb, :controller

  alias Chat.Treatments
  alias Chat.Treatments.Authorization

  def index(conn, params) do
    user = conn.assigns.current_user

    case Treatments.list_queue(user, params) do
      {:ok, %{items: treatments, pagination: pagination}} ->
        items =
          Enum.map(treatments, fn t ->
            %{
              room_id: t.room_id,
              order_id: t.order_id,
              treatment_id: t.id,
              protocol: Treatments.protocol(t),
              status: t.status,
              assigned_agent_id: t.assigned_agent_id,
              assigned_agent_name: if(t.assigned_agent, do: t.assigned_agent.username, else: nil),
              reason:
                if(t.reason,
                  do: %{code: t.reason.code, label: t.reason.label},
                  else: nil
                ),
              can_assign:
                Authorization.eligible_for_assignment?(
                  user,
                  t.status,
                  t.assigned_agent_id
                ),
              inserted_at: t.inserted_at,
              assigned_at: t.assigned_at
            }
          end)

        json(conn, %{items: items, pagination: pagination})

      {:error, :invalid_limit} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_limit", message: "limit must be an integer between 1 and 100"})

      {:error, :invalid_cursor} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_cursor", message: "cursor is invalid"})
    end
  end
end
