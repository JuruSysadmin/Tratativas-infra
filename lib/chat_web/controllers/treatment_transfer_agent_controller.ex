defmodule ChatWeb.TreatmentTransferAgentController do
  @moduledoc "HTTP endpoint for querying eligible transfer agents for a Treatment."

  use ChatWeb, :controller

  alias Chat.Treatments

  def index(conn, %{"room_id" => room_id}) do
    user = conn.assigns.current_user

    case Treatments.list_transfer_candidates(room_id, user) do
      {:ok, candidates} ->
        json(conn, %{agents: candidates})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "not_authorized"})

      {:error, :not_assigned_agent} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "not_assigned_agent"})

      {:error, :invalid_status} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid_status"})

      {:error, :invalid_id} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_id"})
    end
  end
end
