defmodule ChatWeb.ChatLayoutTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias ChatWeb.RoomSidebarComponent

  test "renders an actionable Carbon empty state and accessible collapsible panel" do
    chat_area =
      File.read!(
        Path.expand("../../../lib/chat_web/live/components/chat_area_component.ex", __DIR__)
      )

    presence_panel =
      File.read!(
        Path.expand("../../../lib/chat_web/live/components/presence_panel_component.ex", __DIR__)
      )

    css = File.read!(Path.expand("../../../assets/css/app.css", __DIR__))

    assert chat_area =~ ~s(id="conversation-empty-state")
    assert chat_area =~ "Comece criando uma sala"
    assert chat_area =~ "Comece uma conversa"
    assert chat_area =~ ~s(id="empty-state-primary-action")
    assert presence_panel =~ ~s(JS.toggle_class)
    assert presence_panel =~ ~s(presence-panel--collapsed)

    assert css =~ "width: 200px"
    assert css =~ ".presence-panel--collapsed"
    assert css =~ "width: 48px"
    assert css =~ "text-align: left"
  end

  test "chat layout reserves the mobile viewport for the composer and scrollable messages" do
    css = File.read!(Path.expand("../../../assets/css/app.css", __DIR__))

    assert css =~ "min-height: 0;"
    assert css =~ "height: 100dvh;"
    assert css =~ "padding: 8px 12px calc(8px + env(safe-area-inset-bottom));"

    assert css =~ "@media (min-width: 641px)"
    assert css =~ "@media (min-width: 901px)"
    assert css =~ "overscroll-behavior: contain;"
  end

  test "conversation empty state follows the Carbon illustration, text and action anatomy" do
    chat_area =
      File.read!(
        Path.expand("../../../lib/chat_web/live/components/chat_area_component.ex", __DIR__)
      )

    css = File.read!(Path.expand("../../../assets/css/app.css", __DIR__))

    assert chat_area =~ ~s(class="empty-state-illustration" aria-hidden="true")
    assert chat_area =~ ~s(class="empty-state-body")
    assert chat_area =~ ~s(name="carbon-ibm-watsonx-assistant")
    assert css =~ ".empty-state-illustration"
    assert css =~ ".empty-state-body"
  end

  test "room section titles use the Carbon compact heading scale" do
    css = File.read!(Path.expand("../../../assets/css/app.css", __DIR__))

    assert css =~ """
           .room-section-header h2 {
             font: var(--cds-heading-compact-01);
           }
           """
  end

  test "new room icon exposes an explicit accessible Carbon tooltip" do
    html =
      render_component(&RoomSidebarComponent.room_sidebar/1,
        rooms: [],
        unread_counts: %{},
        navigation_open: false
      )

    assert html =~ ~s(phx-click="open_new_room")
    assert html =~ ~s(aria-label="Criar nova sala")
    assert html =~ ~s(data-tooltip="Criar nova sala")

    css = File.read!(Path.expand("../../../assets/css/app.css", __DIR__))

    assert css =~ ".sidebar-action[data-tooltip]::after"
    assert css =~ ".sidebar-action[data-tooltip]:hover::after"
    assert css =~ ".sidebar-action[data-tooltip]:focus-visible::after"
  end

  test "sidebar replaces empty room sections with a productive no-data state" do
    html =
      render_component(&RoomSidebarComponent.room_sidebar/1,
        rooms: [],
        unread_counts: %{},
        navigation_open: false
      )

    assert html =~ ~s(id="sidebar-empty-state")
    assert html =~ ~s(aria-labelledby="sidebar-empty-state-title")
    assert html =~ "Comece criando uma sala"
    assert html =~ "Suas salas e conversas aparecerão aqui."
    assert html =~ ~s(class="btn-ghost sidebar-empty-state-action")
    assert html =~ ~s(phx-click="open_new_room")
    assert html =~ ~s(class="sidebar-empty-state-icon")
    assert html =~ "M28 2h-10c-1.1035"
    assert html =~ "M17 15V6h-2v9H6"
    refute html =~ "Nenhuma sala"
    refute html =~ ~s(id="pinned-rooms-heading")
    refute html =~ ~s(id="conversation-rooms-heading")
  end

  test "sidebar empty-state action uses the Carbon ghost button treatment" do
    css = File.read!(Path.expand("../../../assets/css/app.css", __DIR__))

    assert css =~ """
           .btn-ghost {
             color: var(--cds-link-primary);
             background: transparent;
             border: 0;
           }
           """
  end

  test "sidebar keeps room sections when room data is available" do
    room = %{id: "room-1", name: "Geral", pinned_at: nil, members: []}

    html =
      render_component(&RoomSidebarComponent.room_sidebar/1,
        rooms: [room],
        current_room: nil,
        unread_counts: %{},
        navigation_open: false
      )

    refute html =~ ~s(id="sidebar-empty-state")
    refute html =~ ~s(id="pinned-rooms-heading")
    assert html =~ ~s(id="conversation-rooms-heading")
    assert html =~ "Geral"
  end
end
