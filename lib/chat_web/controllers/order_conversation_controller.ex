defmodule ChatWeb.OrderConversationController do
  use ChatWeb, :controller

  alias Chat.Rooms
  alias Chat.Treatments

  def index(conn, %{"order_ids" => order_ids}) when is_binary(order_ids) do
    user_id = conn.assigns.current_user.id

    case parse_order_ids(order_ids) do
      {:ok, order_ids} ->
        conversations =
          user_id
          |> Rooms.list_user_order_conversations(order_ids)
          |> Enum.map(fn room -> %{order_id: room.order_id, room_id: room.id} end)

        json(conn, %{conversations: conversations})

      :error ->
        invalid_order_ids(conn)
    end
  end

  def index(conn, _params), do: invalid_order_ids(conn)

  def create(conn, %{"order_id" => order_id}) when is_integer(order_id) do
    open_conversation(conn, order_id)
  end

  def create(conn, %{"order_id" => order_id}) when is_binary(order_id) do
    case Integer.parse(order_id) do
      {order_id, ""} -> open_conversation(conn, order_id)
      _other -> invalid_order_id(conn)
    end
  end

  def create(conn, _params), do: invalid_order_id(conn)

  defp open_conversation(conn, order_id) do
    case Treatments.open_for_order(order_id, conn.assigns.current_user.id) do
      {:ok, %{room: room, treatment: treatment}} ->
        conn
        |> put_status(:created)
        |> json(%{
          conversation: %{
            order_id: room.order_id,
            room_id: room.id,
            treatment_protocol: Treatments.protocol(treatment)
          }
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "order_conversation_not_found"})

      {:error, _reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "order_conversation_unavailable"})
    end
  end

  defp parse_order_ids(value) do
    order_ids =
      value
      |> String.split(",", trim: true)
      |> Enum.map(&Integer.parse/1)

    if order_ids != [] and Enum.all?(order_ids, &match?({_, ""}, &1)) do
      {:ok, order_ids |> Enum.map(&elem(&1, 0)) |> Enum.uniq()}
    else
      :error
    end
  end

  defp invalid_order_ids(conn) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "invalid_order_ids"})
  end

  defp invalid_order_id(conn) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "invalid_order_id"})
  end
end
