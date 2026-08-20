defmodule ChatWeb.NotificationPanelComponent do
  @moduledoc "Carbon notification panel for persisted message mentions."

  use Phoenix.Component

  import ChatWeb.CoreComponents
  alias Phoenix.LiveView.JS

  attr :notifications, :list, required: true

  def notification_panel(assigns) do
    ~H"""
    <aside
      id="notification-panel"
      class="notification-panel"
      role="region"
      aria-label="Notificações"
      phx-mounted={JS.focus_first()}
      phx-window-keydown={JS.push("close_notification_panel") |> JS.focus(to: "#notification-toggle")}
      phx-key="Escape"
    >
      <header class="notification-panel-header">
        <h2>Notificações</h2>
        <button
          type="button"
          class="notification-panel-close"
          phx-click={JS.push("close_notification_panel") |> JS.focus(to: "#notification-toggle")}
          aria-label="Fechar notificações"
        >
          <.icon name="carbon-close" />
        </button>
      </header>

      <div :if={@notifications == []} class="notification-panel-empty" role="status">
        <.icon name="carbon-notification" />
        <p>Você não possui notificações.</p>
      </div>

      <ul :if={@notifications != []} class="notification-list" aria-label="Menções recentes">
        <li :for={mention <- @notifications}>
          <button
            id={"notification-#{mention.message_id}"}
            type="button"
            class="notification-item"
            phx-click="open_notification"
            phx-value-message_id={mention.message_id}
          >
            <span class="notification-item-icon" aria-hidden="true">@</span>
            <span class="notification-item-content">
              <span class="notification-item-title">
                <strong>{mention.message.user.username}</strong> mencionou você
              </span>
              <span class="notification-item-body">{mention.message.content}</span>
              <span class="notification-item-meta">
                {mention.message.room.name} · {format_time(mention.inserted_at)}
              </span>
            </span>
          </button>
        </li>
      </ul>
    </aside>
    """
  end

  attr :notification, :any, default: nil

  def mention_notification_toast(assigns) do
    ~H"""
    <div
      :if={@notification}
      id="mention-notification-toast"
      class="mention-notification-toast"
      role="status"
      aria-live="polite"
    >
      <span class="notification-toast-icon" aria-hidden="true">@</span>
      <span class="notification-toast-content">
        <strong>{@notification.message.user.username} mencionou você</strong>
        <span>{@notification.message.room.name}</span>
      </span>
      <button
        id="dismiss-mention-notification"
        type="button"
        phx-click="dismiss_mention_notification"
        aria-label="Fechar notificação"
      >
        <.icon name="carbon-close" />
      </button>
    </div>
    """
  end

  defp format_time(datetime), do: ChatWeb.Time.format(datetime, "%d/%m · %H:%M")
end
