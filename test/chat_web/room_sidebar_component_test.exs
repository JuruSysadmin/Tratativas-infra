defmodule ChatWeb.RoomSidebarComponentTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias ChatWeb.RoomSidebarComponent

  test "renders active room, pinned/recent groups and accessible previews" do
    pinned_room = room("pinned", "Operações", DateTime.utc_now(), "Mensagem fixada")

    active_room =
      room(
        "active",
        "Sala com um nome muito comprido para truncar",
        nil,
        "Última mensagem da sala"
      )

    html =
      render_component(&RoomSidebarComponent.room_sidebar/1,
        rooms: [pinned_room, active_room],
        current_room: active_room,
        unread_counts: %{"active" => 120},
        mention_unread_count: 0,
        navigation_open: false
      )

    assert html =~ ~s(id="pinned-rooms-heading")
    assert html =~ ~s(id="conversation-rooms-heading")
    assert html =~ ~s(aria-current="page")
    assert html =~ ~s(class="room-list-preview")
    assert html =~ ~s(title="Última mensagem da sala")
    assert html =~ ~s(title="Sala com um nome muito comprido para truncar")
    assert html =~ ~s(aria-label="120 mensagens não lidas")
    assert html =~ "99+"
    refute html =~ ~s(class="room-list-time")
  end

  test "renders the WhatsApp-style conversation row anatomy" do
    html =
      render_component(&RoomSidebarComponent.room_sidebar/1,
        rooms: [room("wpp", "Equipe", nil, "Até logo")],
        current_room: nil,
        unread_counts: %{"wpp" => 2},
        mention_unread_count: 0,
        navigation_open: false
      )

    assert html =~ ~s(class="room-avatar")
    assert html =~ ~s(aria-hidden="true">E</span>)
    assert html =~ ~s(class="room-list-main")
    assert html =~ ~s(class="room-list-preview")
    assert html =~ "room-list-unread"
  end

  test "renders a mention indicator on the matching conversation" do
    html =
      render_component(&RoomSidebarComponent.room_sidebar/1,
        rooms: [room("mentioned", "Equipe", nil, "Veja isto")],
        current_room: nil,
        unread_counts: %{},
        mention_unread_counts: %{"mentioned" => 2},
        mention_unread_count: 2,
        navigation_open: false
      )

    assert html =~ ~s(class="room-list-mention")
    assert html =~ ~s(aria-label="2 menções não lidas")
    refute html =~ ~s(id="mentions-summary")
  end

  test "shows order context instead of room navigation for an order room" do
    order_room = room("order-room", "Pedido #9998043469", nil, nil)
    order_room = Map.put(order_room, :order_id, 9_998_043_469)

    html =
      render_component(&RoomSidebarComponent.room_sidebar/1,
        rooms: [order_room],
        current_room: order_room,
        unread_counts: %{},
        mention_unread_count: 0,
        navigation_open: false
      )

    assert html =~ ~s(class="order-context-sidebar")
    assert html =~ "491564 - LORELEY ANDRADE"
    assert html =~ "Itens do pedido"
    assert html =~ "MASSA ACRILICA 20KG VELOZ BD"
    assert html =~ ~s(class="delivery-priority-badge")
    assert html =~ ~s(data-priority="Média")
    assert html =~ ~s(class="delivery-priority-label">Prioridade:</span>)
    refute html =~ ~r/class="delivery-priority-badge"[^>]*>\s*Prioridade:/
    assert html =~ "Status da entrega"
    assert html =~ "LIBERADO"
    refute html =~ "Pedidos relacionados"
    refute html =~ "9998043470"
    refute html =~ "TV8"
    refute html =~ ~s(id="conversation-rooms-heading")
  end

  test "shows an explicit empty preview for rooms without messages" do
    html =
      render_component(&RoomSidebarComponent.room_sidebar/1,
        rooms: [room("empty", "Sem mensagens", nil, nil)],
        current_room: nil,
        unread_counts: %{},
        mention_unread_count: 0,
        navigation_open: false
      )

    assert html =~ "Sem mensagens"
  end

  test "uses compact room rows without item borders and separates sections" do
    css = File.read!(Path.expand("../../assets/css/app.css", __DIR__))

    assert css =~ ".sidebar-list li {\n  border-bottom: 0;\n}"

    assert css =~
             ".room-section + .room-section {\n  border-top: 1px solid var(--cds-border-subtle-01);\n}"

    assert css =~ "min-height: 72px;"
    assert css =~ "padding: 10px 12px;"
  end

  test "uses the Carbon highlight layer for the active room" do
    css = File.read!(Path.expand("../../assets/css/app.css", __DIR__))

    assert css =~ ".sidebar-list li:active,\n.sidebar-list li.active {"
    assert css =~ "background: var(--cds-highlight);"
  end

  test "does not render an empty pinned section" do
    html =
      render_component(&RoomSidebarComponent.room_sidebar/1,
        rooms: [room("room-1", "Geral", nil, nil)],
        current_room: nil,
        unread_counts: %{},
        navigation_open: false
      )

    refute html =~ ~s(id="pinned-rooms-heading")
    assert html =~ ~s(id="conversation-rooms-heading")
  end

  defp room(id, name, pinned_at, preview) do
    %{
      id: id,
      name: name,
      pinned_at: pinned_at,
      last_message_preview: preview,
      members: []
    }
  end
end
