defmodule ChatWeb.TreatmentAssignmentController do
  @moduledoc "HTTP endpoint for assigning an eligible Treatment to the current user."

  use ChatWeb, :controller

  alias Chat.Broadcaster
  alias Chat.Realtime.Payloads
  alias Chat.Rooms
  alias Chat.Treatments

  def create(conn, %{"treatment_id" => treatment_id}) do
    user = conn.assigns.current_user

    case Treatments.assign_agent_by_id(treatment_id, user) do
      {:ok, treatment, :assigned} ->
        payload = assignment_payload(treatment)
        Broadcaster.broadcast_treatment_assigned(treatment.room_id, payload)
        notify_treatment_creator(treatment, payload)
        Broadcaster.broadcast_treatment_updated(Payloads.treatment(treatment))
        json(conn, payload)

      {:ok, treatment, :idempotent} ->
        json(conn, assignment_payload(treatment))

      {:error, :invalid_id} ->
        error(conn, :bad_request, "invalid_id")

      {:error, reason}
      when reason in [:forbidden, :already_assigned, :not_found, :invalid_status] ->
        error(conn, status_for(reason), Atom.to_string(reason))

      _unexpected_result ->
        error(conn, :unprocessable_entity, "treatment_assignment_failed")
    end
  end

  def create(conn, _params), do: error(conn, :bad_request, "invalid_treatment_id")

  defp assignment_payload(treatment) do
    %{
      treatment_id: treatment.id,
      status: treatment.status,
      assigned_agent_id: treatment.assigned_agent_id,
      assigned_at: treatment.assigned_at,
      sla_paused_seconds: treatment.sla_paused_seconds,
      assigned_agent_username: treatment.assigned_agent.username
    }
  end

  defp notify_treatment_creator(treatment, payload) do
    room = Rooms.get_room!(treatment.room_id)

    Broadcaster.broadcast_treatment_assigned_to_user(room.creator_id, %{
      treatment_id: payload.treatment_id,
      room_id: treatment.room_id,
      order_id: room.order_id,
      assigned_agent_id: payload.assigned_agent_id,
      assigned_agent_username: payload.assigned_agent_username,
      assigned_at: payload.assigned_at
    })
  end

  defp status_for(:forbidden), do: :forbidden
  defp status_for(:not_found), do: :not_found
  defp status_for(:already_assigned), do: :conflict
  defp status_for(:invalid_status), do: :unprocessable_entity

  defp error(conn, status, reason) do
    conn
    |> put_status(status)
    |> json(%{error: reason})
  end
end
