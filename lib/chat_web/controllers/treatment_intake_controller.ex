defmodule ChatWeb.TreatmentIntakeController do
  @moduledoc "HTTP endpoints for explicit Commercial Treatment intake."

  use ChatWeb, :controller

  alias Chat.Treatments

  def show(conn, %{"order_id" => order_id}) do
    case parse_order_id(order_id) do
      {:ok, parsed_order_id} ->
        case Treatments.intake_state(parsed_order_id) do
          {:missing, reasons} ->
            json(conn, %{state: "missing", reasons: Enum.map(reasons, &reason_json/1)})

          {:existing, _treatment} ->
            json(conn, %{state: "existing"})
        end

      :error ->
        invalid_order_id(conn)
    end
  end

  def create(conn, %{"order_id" => order_id} = params) do
    with {:ok, order_id} <- parse_order_id(order_id),
         {:ok, %{room: room, treatment: treatment}} <-
           Treatments.open_structured_for_order(order_id, conn.assigns.current_user.id, %{
             reason_code: params["reason_code"],
             initial_description: params["initial_description"]
           }) do
      conn
      |> put_status(:created)
      |> json(%{
        conversation: %{
          order_id: room.order_id,
          room_id: room.id,
          treatment_protocol: Treatments.protocol(treatment)
        }
      })
    else
      :error -> invalid_order_id(conn)
      {:error, :treatment_exists} -> conflict(conn, "treatment_already_exists")
      {:error, :invalid_reason} -> unprocessable(conn, "invalid_treatment_reason")
      {:error, :invalid_description} -> unprocessable(conn, "invalid_initial_description")
      {:error, _reason} -> unprocessable(conn, "treatment_intake_unavailable")
    end
  end

  def create(conn, _params), do: invalid_order_id(conn)

  defp parse_order_id(order_id) when is_integer(order_id), do: {:ok, order_id}

  defp parse_order_id(order_id) when is_binary(order_id) do
    case Integer.parse(order_id) do
      {value, ""} -> {:ok, value}
      _other -> :error
    end
  end

  defp parse_order_id(_order_id), do: :error

  defp reason_json(reason), do: %{code: reason.code, label: reason.label}

  defp invalid_order_id(conn),
    do: conn |> put_status(:bad_request) |> json(%{error: "invalid_order_id"})

  defp conflict(conn, error), do: conn |> put_status(:conflict) |> json(%{error: error})

  defp unprocessable(conn, error),
    do: conn |> put_status(:unprocessable_entity) |> json(%{error: error})
end
