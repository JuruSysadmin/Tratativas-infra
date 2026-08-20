defmodule ChatWeb.ChatAreaComponent do
  @moduledoc """
  Componente da área principal de chat.
  """

  use Phoenix.Component

  import ChatWeb.CoreComponents
  import ChatWeb.MessageComponents

  alias Chat.Orders.Mock
  alias ChatWeb.OrderPresentation

  attr :current_room, :any, default: nil
  attr :current_user, :map, required: true
  attr :messages, :any, required: true
  attr :has_more_messages, :boolean, required: true
  attr :pending_messages, :map, required: true
  attr :pending_message_order, :list, required: true
  attr :status_messages, :list, required: true
  attr :typing_users, :list, required: true
  attr :input_text, :string, required: true
  attr :mention_suggestions, :list, default: []
  attr :message_statuses, :map, required: true
  attr :rooms, :list, required: true
  attr :online_users, :list, default: []

  def chat_area(%{current_room: nil} = assigns) do
    ~H"""
    <main class="messages-area" id="main-content" tabindex="-1">
      <.empty_state rooms={@rooms} />
    </main>
    """
  end

  def chat_area(assigns) do
    online_user_ids =
      assigns
      |> Map.get(:online_users, [])
      |> extract_online_user_ids()
      |> MapSet.new()
      |> MapSet.put(Map.get(assigns.current_user, :id))

    assigns =
      assigns
      |> Map.put(:online_user_ids, online_user_ids)
      |> Map.put(:status_messages, normalize_status_messages(assigns.status_messages))
      |> Map.put(:typing_users, normalize_typing_users(assigns.typing_users))
      |> Map.put(
        :grouped_message_ids,
        grouped_message_ids(assigns.messages)
      )
      |> Map.put(
        :grouped_pending_ids,
        grouped_pending_ids(assigns.pending_message_order, assigns.pending_messages)
      )

    ~H"""
    <main class="messages-area" id="main-content" tabindex="-1">
      <.room_header room={@current_room} current_user={@current_user} />

      <.message_loading_indicator />

      <button
        :if={@has_more_messages}
        id="load-older-messages"
        type="button"
        class="load-older-messages"
        phx-click="load_older_messages"
      >
        Carregar mensagens anteriores
      </button>

      <div
        class="messages-list messages-container"
        id="messages-list"
        phx-hook="MarkRead"
        phx-update="stream"
        phx-viewport-top="load_older_messages"
      >
        <.message_item
          :for={{dom_id, msg} <- @messages}
          dom_id={dom_id}
          msg={msg}
          current_user={@current_user}
          message_statuses={@message_statuses}
          online_user_ids={@online_user_ids}
          compact={MapSet.member?(@grouped_message_ids, msg.id)}
        />
      </div>

      <div
        id="pending-messages"
        class="pending-messages"
        aria-live="polite"
        phx-hook="PendingMessages"
        data-pending-storage-key={"chat:pending:#{@current_room.id}"}
      >
        <.pending_message
          :for={pending_id <- Enum.filter(@pending_message_order, &Map.has_key?(@pending_messages, &1))}
          msg={@pending_messages[pending_id]}
          compact={MapSet.member?(@grouped_pending_ids, pending_id)}
        />
      </div>

      <div
        :for={status <- @status_messages}
        class="conversation-status"
        role="status"
      >
        <%= if status.kind == :joined do %>
          <%= status.username %> entrou na sala
        <% else %>
          <%= status.username %> saiu da sala
        <% end %>
      </div>

      <%= case @typing_users do %>
        <% [_ | _] -> %>
          <div class="typing-indicator">
            <span class="typing-usernames"><%= Enum.map_join(@typing_users, ", ", & &1.username) %></span>
            está digitando...
          </div>
        <% [] -> %>
      <% end %>

      <.message_form
        input_text={@input_text}
        mention_suggestions={@mention_suggestions}
        room_id={@current_room.id}
      />
    </main>
    """
  end

  defp room_header(assigns) do
    member_count = length(assigns.room.members)
    order_id = room_order_id(assigns.room)
    order = if is_integer(order_id), do: Mock.get(order_id)
    delivery = if order, do: order |> Map.get(:related_deliveries, []) |> Enum.at(0)

    assigns =
      assigns
      |> assign(:member_count, member_count)
      |> assign(:order, order)
      |> assign(:delivery, delivery)

    ~H"""
    <div class="room-header">
      <div class="room-header-content">
        <h1 id="chat-room-title"><%= @room.name %></h1>
        <span class="room-member-summary" aria-label={"#{@member_count} membros na sala"}>
          <%= @member_count %> <%= if @member_count == 1, do: "membro", else: "membros" %>
        </span>
        <div :if={@order} class="room-order-summary" aria-label="Resumo do pedido">
          <span class="room-order-type">
            {OrderPresentation.type_label(@order.order_type)}
          </span>
          <span class="room-order-status">{@order.status}</span>
          <span>R$ {:erlang.float_to_binary(@order.amount, decimals: 2)}</span>
          <span :if={@delivery}>Entrega: {@delivery.status}</span>
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
      </div>
      <%= if @room.creator_id == @current_user.id do %>
        <button
          type="button"
          class="room-header-action room-header-action--danger"
          phx-click="confirm_delete_room"
          phx-value-room_id={@room.id}
          aria-label="Excluir sala"
          title="Excluir sala"
        >
          <.icon name="carbon-trash" />
        </button>
      <% else %>
        <button
          type="button"
          class="room-header-action"
          phx-click="leave_room"
          phx-value-room_id={@room.id}
          aria-label={"Sair da sala " <> @room.name}
          title="Sair da sala"
        >
          Sair da sala
        </button>
      <% end %>
    </div>
    """
  end

  defp room_order_id(%{order_id: order_id}), do: order_id
  defp room_order_id(_room), do: nil

  defp message_loading_indicator(assigns) do
    ~H"""
    <div
      id="messages-loading"
      class="messages-loading"
      role="status"
      aria-live="polite"
      phx-hook="MessageLoading"
      data-initial-loading
    >
      <svg class="messages-loading-spinner" viewBox="0 0 100 100" aria-hidden="true">
        <circle class="messages-loading-track" cx="50" cy="50" r="42" />
        <circle class="messages-loading-stroke" cx="50" cy="50" r="42" />
      </svg>
      <span>Carregando mensagens…</span>
    </div>
    """
  end

  defp extract_online_user_ids(online_users) do
    Enum.flat_map(online_users, fn
      user when is_map(user) ->
        case Map.get(user, :id) do
          nil -> []
          user_id -> [user_id]
        end

      _invalid_user ->
        []
    end)
  end

  defp normalize_status_messages(status_messages) do
    Enum.map(status_messages, fn
      status when is_map(status) ->
        %{
          kind: Map.get(status, :kind, :left),
          username: Map.get(status, :username, "Usuário") || "Usuário"
        }

      _invalid_status ->
        %{kind: :left, username: "Usuário"}
    end)
  end

  defp normalize_typing_users(typing_users) do
    Enum.flat_map(typing_users, fn
      user when is_map(user) ->
        case Map.get(user, :username) do
          username when is_binary(username) and username != "" -> [%{username: username}]
          _missing_username -> []
        end

      _invalid_user ->
        []
    end)
  end

  defp empty_state(assigns) do
    ~H"""
    <section id="conversation-empty-state" class="empty-state" aria-labelledby="empty-state-title">
      <div class="empty-state-content">
        <div class="empty-state-illustration" aria-hidden="true">
          <.icon name="carbon-ibm-watsonx-assistant" />
        </div>
        <div class="empty-state-body">
          <%= if Enum.empty?(@rooms) do %>
            <h2 id="empty-state-title">Comece criando uma sala</h2>
            <p>Crie um espaço para reunir pessoas e trocar mensagens em tempo real.</p>
            <button
              id="empty-state-primary-action"
              type="button"
              class="btn btn-primary"
              phx-click="open_new_room"
            >
              Criar sala
            </button>
          <% else %>
            <h2 id="empty-state-title">Comece uma conversa</h2>
            <p>Abra uma das suas salas para ver o histórico e conversar com a equipe.</p>
            <%= case List.first(@rooms) do %>
              <% %{id: first_room_id} -> %>
                <button
                  id="empty-state-primary-action"
                  type="button"
                  class="btn btn-primary"
                  phx-click="select_room"
                  phx-value-room_id={first_room_id}
                >
                  Abrir primeira sala
                </button>
              <% _ -> %>
            <% end %>
          <% end %>
        </div>
      </div>
    </section>
    """
  end

  defp grouped_message_ids(messages) do
    messages
    |> message_items()
    |> grouped_message_ids_from_items()
  end

  defp message_items(%Phoenix.LiveView.LiveStream{inserts: inserts}) do
    {items, _dom_ids} =
      Enum.reduce(inserts, {[], MapSet.new()}, fn
        {dom_id, _at, message, _limit, _update_only}, {items, dom_ids} ->
          if MapSet.member?(dom_ids, dom_id) do
            {items, dom_ids}
          else
            {[{dom_id, message} | items], MapSet.put(dom_ids, dom_id)}
          end
      end)

    items
  end

  defp message_items(messages), do: messages

  defp grouped_message_ids_from_items(messages) do
    {grouped_ids, _previous_user_id} =
      Enum.reduce(messages, {MapSet.new(), nil}, &grouped_message_item/2)

    grouped_ids
  end

  defp grouped_pending_ids(pending_order, pending_messages) do
    {grouped_ids, _previous_user_id} =
      Enum.reduce(pending_order, {MapSet.new(), nil}, fn pending_id, acc ->
        grouped_pending_item(pending_id, pending_messages, acc)
      end)

    grouped_ids
  end

  defp grouped_message_item({_dom_id, message}, {grouped_ids, previous_user_id}) do
    case message do
      %{id: message_id, user: %{id: user_id}} ->
        {maybe_group_id(grouped_ids, previous_user_id == user_id, message_id), user_id}

      _missing_message ->
        {grouped_ids, previous_user_id}
    end
  end

  defp grouped_pending_item(pending_id, pending_messages, {grouped_ids, previous_user_id}) do
    case Map.get(pending_messages, pending_id) do
      %{user_id: user_id} ->
        {maybe_group_id(grouped_ids, previous_user_id == user_id, pending_id), user_id}

      _missing_message ->
        {grouped_ids, previous_user_id}
    end
  end

  defp maybe_group_id(grouped_ids, true, id), do: MapSet.put(grouped_ids, id)
  defp maybe_group_id(grouped_ids, false, _id), do: grouped_ids
end
