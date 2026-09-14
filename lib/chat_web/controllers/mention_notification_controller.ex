defmodule ChatWeb.MentionNotificationController do
  @moduledoc "HTTP endpoint for the authenticated user's mention notifications."

  use ChatWeb, :controller

  alias Chat.Messages
  alias Chat.Realtime.Payloads

  def index(conn, params) do
    user_id = conn.assigns.current_user.id
    limit = parse_limit(params["limit"])
    notifications = Messages.list_mention_notifications(user_id, limit: limit)

    json(conn, %{
      notifications: Enum.map(notifications, &notification_payload/1),
      unread_count: Messages.count_unread_mentions(user_id)
    })
  end

  def mark_read(conn, %{"message_id" => message_id, "room_id" => room_id}) do
    user_id = conn.assigns.current_user.id

    with {:ok, notification} <- Messages.get_mention_notification(user_id, message_id),
         true <- notification.message.room_id == room_id,
         {_inserted_ids, true} <- Messages.mark_room_read([message_id], user_id, room_id) do
      json(conn, %{unread_count: Messages.count_unread_mentions(user_id)})
    else
      _reason -> send_resp(conn, :not_found, "")
    end
  end

  def mark_read(conn, _params), do: send_resp(conn, :bad_request, "")

  defp notification_payload(%{
         message_id: message_id,
         inserted_at: inserted_at,
         message: %{content: content, room: room, user: user}
       }) do
    %{
      message_id: message_id,
      room_id: room.id,
      room_name: room.name,
      order_id: room.order_id,
      content: content,
      inserted_at: Payloads.iso8601_timestamp(inserted_at),
      user: %{id: user.id, username: user.username}
    }
  end

  defp parse_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {limit, ""} when limit in 1..100 -> limit
      _other -> 50
    end
  end

  defp parse_limit(_value), do: 50
end
