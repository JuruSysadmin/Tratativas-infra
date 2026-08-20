defmodule ChatWeb.ChatNotifications do
  @moduledoc "Maintains the LiveView projection of persisted mention notifications."

  use Phoenix.LiveView

  alias Chat.Messages

  @notification_limit 50

  def init(socket) do
    socket
    |> assign(:notification_panel_open, false)
    |> assign(:mention_toast, nil)
    |> refresh()
  end

  def refresh(socket) do
    notifications =
      socket.assigns.current_user.id
      |> Messages.list_mention_notifications(limit: @notification_limit)

    mention_toast = reconcile_toast(Map.get(socket.assigns, :mention_toast), notifications)

    socket
    |> assign(:mention_notifications, notifications)
    |> assign(:mention_toast, mention_toast)
    |> assign(
      :mention_unread_counts,
      Messages.unread_mention_counts_by_room(
        socket.assigns.current_user.id,
        Enum.map(socket.assigns.rooms, & &1.id)
      )
    )
    |> assign(
      :mention_unread_count,
      Messages.count_unread_mentions(socket.assigns.current_user.id)
    )
  end

  def toggle_panel(socket) do
    update(socket, :notification_panel_open, &(!&1))
  end

  def close_panel(socket) do
    assign(socket, :notification_panel_open, false)
  end

  def show_toast(socket, message_id) do
    assign(socket, :mention_toast, find(socket, message_id))
  end

  def dismiss_toast(socket) do
    assign(socket, :mention_toast, nil)
  end

  def find(socket, message_id) when is_binary(message_id) do
    Enum.find(socket.assigns.mention_notifications, &(&1.message_id == message_id))
  end

  def find(_socket, _message_id), do: nil

  defp reconcile_toast(nil, _notifications), do: nil

  defp reconcile_toast(%{message_id: message_id}, notifications) do
    Enum.find(notifications, &(&1.message_id == message_id))
  end
end
