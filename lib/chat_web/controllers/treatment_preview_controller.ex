defmodule ChatWeb.TreatmentPreviewController do
  use ChatWeb, :controller

  alias Chat.Treatments

  def show(conn, %{"treatment_id" => treatment_id}) do
    current_user = conn.assigns.current_user
    authorization_header = get_req_header(conn, "authorization") |> List.first()

    case Treatments.get_preview(treatment_id, current_user, authorization_header) do
      {:ok, preview} ->
        json(conn, preview)

      {:error, :invalid_id} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "bad_request"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "forbidden"})
    end
  end
end
