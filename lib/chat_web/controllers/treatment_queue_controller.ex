defmodule ChatWeb.TreatmentQueueController do
  @moduledoc "HTTP endpoints for the treatment queue list."

  use ChatWeb, :controller

  alias Chat.Treatments
  alias Chat.Treatments.Authorization

  def index(conn, params) do
    user = conn.assigns.current_user

    case Treatments.list_queue(user, params) do
      {:ok, %{items: treatments, pagination: pagination, counts: counts}} ->
        customer_names =
          treatments
          |> Enum.map(& &1.order_id)
          |> Chat.Orders.CustomerNames.resolve(authorization_header(conn))

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
              customer_name: Map.get(customer_names, t.order_id),
              reason:
                if(t.reason,
                  do: %{code: t.reason.code, label: t.reason.label, priority: t.reason.priority},
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

        json(conn, %{items: items, pagination: pagination, counts: counts})

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

  defp authorization_header(conn) do
    conn
    |> get_req_header("authorization")
    |> List.first()
  end
end
