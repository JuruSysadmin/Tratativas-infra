defmodule ChatWeb.PresencePanelComponent do
  @moduledoc """
  Componente de painel de participantes online.
  """

  use Phoenix.Component

  import ChatWeb.CoreComponents

  alias Phoenix.LiveView.JS

  attr :current_user, :map, required: true
  attr :current_room, :any, required: true
  attr :online_users, :list, required: true

  def presence_panel(%{current_room: nil} = assigns) do
    ~H"""
    """
  end

  def presence_panel(assigns) do
    assigns =
      assign(
        assigns,
        :online_users,
        normalize_online_users(assigns.online_users, assigns.current_user)
      )

    ~H"""
    <aside
      id="presence-panel"
      class="presence-panel"
      aria-label="Participantes da sala"
    >
      <div class="presence-header">
        <span
          class="cds-status-indicator cds-status-indicator--success presence-summary"
          role="status"
          aria-label={"#{length(@online_users) + 1} participantes online"}
        >
          <span class="cds-status-indicator__indicator" aria-hidden="true"></span>
          <span><%= length(@online_users) + 1 %> participantes online</span>
        </span>
        <button
          type="button"
          class="presence-toggle"
          phx-click={
            JS.toggle_class("presence-panel--collapsed", to: "#presence-panel")
            |> JS.toggle_attribute({"aria-expanded", "true", "false"})
          }
          aria-expanded="true"
          aria-controls="presence-list"
          aria-label="Recolher participantes"
          title="Recolher participantes"
        >
          <.icon name="carbon-user" />
        </button>
      </div>
      <ul id="presence-list" class="presence-list">
        <li class="presence-current-user">
          <span class="cds-status-indicator cds-status-indicator--success">
            <span class="cds-status-indicator__indicator" aria-hidden="true"></span>
            <span><%= @current_user.username %> (você)</span>
            <span class="sr-only">online nesta sala</span>
          </span>
        </li>
        <li :for={user <- @online_users}>
          <span class="cds-status-indicator cds-status-indicator--success">
            <span class="cds-status-indicator__indicator" aria-hidden="true"></span>
            <span><%= user.username %></span>
            <span class="sr-only">online nesta sala</span>
          </span>
        </li>
      </ul>
    </aside>
    """
  end

  defp normalize_online_users(online_users, current_user) do
    current_user_id = Map.get(current_user, :id)

    online_users
    |> Enum.reject(&(Map.get(&1, :id) == current_user_id))
    |> Enum.uniq_by(&Map.get(&1, :id))
  end
end
