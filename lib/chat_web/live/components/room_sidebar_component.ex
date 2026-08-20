defmodule ChatWeb.RoomSidebarComponent do
  @moduledoc """
  Componente de navegação lateral de salas.
  """

  use Phoenix.Component

  import ChatWeb.CoreComponents

  alias Chat.Orders.Mock
  alias ChatWeb.OrderPresentation

  attr :rooms, :list, required: true
  attr :current_room, :any, default: nil
  attr :unread_counts, :map, required: true
  attr :mention_unread_counts, :map, default: %{}
  attr :mention_unread_count, :integer, default: 0
  attr :navigation_open, :boolean, required: true

  def room_sidebar(assigns) do
    assigns =
      assigns
      |> assign(:pinned_rooms, Enum.filter(assigns.rooms, & &1.pinned_at))
      |> assign(:conversation_rooms, Enum.reject(assigns.rooms, & &1.pinned_at))
      |> assign(:order, order_for_room(assigns.current_room))

    ~H"""
    <nav
      id="room-navigation"
      class={["sidebar", @navigation_open && "sidebar--open"]}
      aria-label="Salas"
    >
      <div class="sidebar-header">
        <span>Conversas</span>
        <div class="sidebar-actions">
          <button
            type="button"
            class="sidebar-action"
            phx-click="open_room_explorer"
            aria-label="Explorar salas"
            title="Explorar salas"
          >
            <.icon name="carbon-search" />
          </button>
          <button
            type="button"
            class="sidebar-action"
            phx-click="open_new_room"
            aria-label="Criar nova sala"
            data-tooltip="Criar nova sala"
          >
            <.icon name="carbon-add" />
          </button>
        </div>
      </div>
      <div class="sidebar-content">
        <span
          :if={@mention_unread_count > 0}
          id="mention-unread-count"
          class="sr-only"
          aria-label={"#{@mention_unread_count} menções não lidas"}
        >
          {@mention_unread_count}
        </span>

        <%= if @order do %>
          <.order_context order={@order} />
        <% else %>
          <%= if Enum.empty?(@rooms) do %>
          <section
            id="sidebar-empty-state"
            class="sidebar-empty-state"
            aria-labelledby="sidebar-empty-state-title"
          >
            <h2 id="sidebar-empty-state-title">Comece criando uma sala</h2>
            <p>Suas salas e conversas aparecerão aqui.</p>
            <button
              type="button"
              class="btn-ghost sidebar-empty-state-action"
              phx-click="open_new_room"
            >
              <.icon name="carbon-ibm-watsonx-assistant" class="sidebar-empty-state-icon" />
              <span>Criar sala</span>
            </button>
          </section>
        <% else %>
          <section :if={@pinned_rooms != []} class="room-section" aria-labelledby="pinned-rooms-heading">
            <div class="room-section-header">
              <h2 id="pinned-rooms-heading">Fixadas</h2>
              <span aria-label={"#{length(@pinned_rooms)} salas fixadas"}>
                {length(@pinned_rooms)}
              </span>
            </div>
            <.room_list
              id="pinned-rooms"
              rooms={@pinned_rooms}
              current_room={@current_room}
              unread_counts={@unread_counts}
              mention_unread_counts={@mention_unread_counts}
              pinned
            />
          </section>

          <section
            :if={@conversation_rooms != []}
            class="room-section"
            aria-labelledby="conversation-rooms-heading"
          >
            <div class="room-section-header">
              <h2 id="conversation-rooms-heading">Recentes</h2>
              <span aria-label={"#{length(@conversation_rooms)} salas recentes"}>
                {length(@conversation_rooms)}
              </span>
            </div>
            <.room_list
              id="conversation-rooms"
              rooms={@conversation_rooms}
              current_room={@current_room}
              unread_counts={@unread_counts}
              mention_unread_counts={@mention_unread_counts}
            />
          </section>
          <% end %>
        <% end %>
      </div>
    </nav>
    """
  end

  defp order_context(assigns) do
    delivery = assigns.order |> Map.get(:related_deliveries, []) |> Enum.at(0)
    assigns = assign(assigns, :delivery, delivery)

    ~H"""
    <section class="order-context-sidebar" aria-labelledby="order-context-title">
      <div class="order-context-sidebar-header">
        <p class="sidebar-eyebrow">Tratativa</p>
        <h2 id="order-context-title">Pedido #{@order.order_id}</h2>
        <div
          :if={@delivery && Map.get(@delivery, :delivery_priority) in ["Alta", "Média", "Baixa"]}
          class="delivery-priority"
        >
          <span class="delivery-priority-label">Prioridade:</span>
          <span class="delivery-priority-badge" data-priority={@delivery.delivery_priority}>
            {@delivery.delivery_priority}
          </span>
        </div>
      </div>

      <dl class="order-context-details">
        <div>
          <dt>Cliente</dt>
          <dd>{@order.customer_name}</dd>
        </div>
        <div>
          <dt>Tipo</dt>
          <dd>{OrderPresentation.type_label(@order.order_type)}</dd>
        </div>
        <div>
          <dt>Status do pedido</dt>
          <dd>{@order.status}</dd>
        </div>
        <div :if={@delivery}>
          <dt>Status da entrega</dt>
          <dd>{@delivery.status}</dd>
        </div>
        <div>
          <dt>Valor</dt>
          <dd>R$ {:erlang.float_to_binary(@order.amount, decimals: 2)}</dd>
        </div>
        <div>
          <dt>Entrega</dt>
          <dd>{@order.delivery.place}</dd>
        </div>
        <div>
          <dt>Cidade</dt>
          <dd>{@order.delivery.city}/{@order.delivery.state}</dd>
        </div>
      </dl>

      <div class="order-context-items">
        <h3>Itens do pedido</h3>
        <ul>
          <li :for={item <- @order.items}>
            <strong>{item.description}</strong>
            <span>{item.quantity} unidade(s) · R$ {:erlang.float_to_binary(item.total, decimals: 2)}</span>
          </li>
        </ul>
      </div>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :rooms, :list, required: true
  attr :current_room, :any, required: true
  attr :unread_counts, :map, required: true
  attr :mention_unread_counts, :map, default: %{}
  attr :pinned, :boolean, default: false

  defp room_list(assigns) do
    ~H"""
    <ul id={@id} class="sidebar-list">
      <li
        :for={room <- @rooms}
        id={"sidebar-room-#{room.id}"}
        class={if @current_room && @current_room.id == room.id, do: "active"}
        data-room-id={room.id}
      >
        <div class="room-list-row">
          <button
            type="button"
            id={"room-select-#{room.id}"}
            class="room-list-button"
            phx-click="select_room"
            phx-value-room_id={room.id}
            aria-current={if @current_room && @current_room.id == room.id, do: "page"}
            title={room.name}
          >
            <span class="room-avatar" aria-hidden="true">{room_initial(room.name)}</span>
            <span class="room-list-main">
              <span class="room-list-heading">
                <span class="room-list-name">{room.name}</span>

              </span>
              <span class="room-list-preview" title={room_preview(room)}>
                {room_preview(room)}
              </span>
            </span>
            <span
              :if={mention_unread_count(@mention_unread_counts, room.id) > 0}
              class="room-list-mention"
              aria-label={mention_unread_label(@mention_unread_counts, room.id)}
            >
              @
            </span>
            <span
              :if={unread_count(@unread_counts, room.id) > 0}
              class="room-list-unread room-unread-count"
              aria-label={unread_label(@unread_counts, room.id)}
            >
              {unread_badge(@unread_counts, room.id)}
            </span>
          </button>
          <button
            type="button"
            id={"room-pin-#{room.id}"}
            class="room-pin-button"
            phx-click={if @pinned, do: "unpin_room", else: "pin_room"}
            phx-value-room_id={room.id}
            aria-pressed={to_string(@pinned)}
            aria-label={if @pinned, do: "Desfixar #{room.name}", else: "Fixar #{room.name}"}
            title={if @pinned, do: "Desfixar", else: "Fixar"}
          >
            <.icon name="carbon-pin" />
          </button>
        </div>
      </li>
    </ul>
    """
  end

  defp room_initial(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.first()
    |> case do
      nil -> "?"
      initial -> String.upcase(initial)
    end
  end

  defp room_initial(_name), do: "?"

  defp order_for_room(%{order_id: order_id}) when is_integer(order_id), do: Mock.get(order_id)
  defp order_for_room(_room), do: nil

  defp room_preview(room) do
    case Map.get(room, :last_message_preview) do
      preview when is_binary(preview) and preview != "" -> String.trim(preview)
      _empty -> "Sem mensagens"
    end
  end

  defp unread_count(unread_counts, room_id), do: Map.get(unread_counts, room_id, 0)

  defp mention_unread_count(mention_unread_counts, room_id),
    do: Map.get(mention_unread_counts, room_id, 0)

  defp mention_unread_label(mention_unread_counts, room_id) do
    "#{mention_unread_count(mention_unread_counts, room_id)} menções não lidas"
  end

  defp unread_badge(unread_counts, room_id) do
    case unread_count(unread_counts, room_id) do
      count when count > 99 -> "99+"
      count -> to_string(count)
    end
  end

  defp unread_label(unread_counts, room_id) do
    "#{unread_count(unread_counts, room_id)} mensagens não lidas"
  end
end
