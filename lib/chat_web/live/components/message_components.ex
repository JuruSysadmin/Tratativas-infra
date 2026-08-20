defmodule ChatWeb.MessageComponents do
  @moduledoc """
  Componentes auxiliares para renderização de mensagens no chat.
  """

  use Phoenix.Component

  import ChatWeb.CoreComponents

  # ---------------------------------------------------------------------------
  # Message item
  # ---------------------------------------------------------------------------

  attr :dom_id, :string, required: true
  attr :msg, :map, required: true
  attr :current_user, :map, required: true
  attr :message_statuses, :map, required: true
  attr :online_user_ids, :any, required: true
  attr :compact, :boolean, default: false

  def message_item(assigns) do
    msg = assigns.msg
    current_user_id = assigns.current_user.id

    assigns =
      assigns
      |> assign(:is_own_message, msg.user.id == current_user_id)
      |> assign(:status, Map.get(msg, :status, :sent))
      |> assign(:message_status, Map.get(assigns.message_statuses, msg.id))
      |> assign(:segments, message_segments(msg))
      |> assign(:author_online, MapSet.member?(assigns.online_user_ids, msg.user.id))
      |> assign(:deletable?, message_deletable?(msg, current_user_id))

    ~H"""
    <div
      id={@dom_id}
      tabindex="-1"
      data-message-id={@msg.id}
      data-mark-readable={
        if !@is_own_message && @status not in [:sending, :failed], do: "true"
      }
      class={
        "message #{if @is_own_message, do: "message--user", else: "message--bot"}#{
          if @compact, do: " message--grouped", else: ""
        }"
      }
    >
      <div class="message-avatar-wrapper">
        <div class={"message-avatar #{if @is_own_message, do: "message-avatar--gray", else: "message-avatar--blue"}"}>
          <%= String.first(@msg.user.username) |> String.upcase() %>
        </div>
        <span
          :if={@author_online && !@is_own_message}
          class="message-avatar-online-indicator"
          aria-hidden="true"
        ></span>
      </div>
      <div class="message-body">
        <div class="message-metadata">
          <span class="message-author"><%= if @is_own_message, do: "Você", else: @msg.user.username %></span>
          <span class="message-time"><%= ChatWeb.Time.format(@msg.inserted_at, "%H:%M") %></span>
          <%= if Map.get(@msg, :edited_at) do %>
            <span class="message-edited" title={message_edited_tooltip(@msg.edited_at)}>editada</span>
          <% end %>
        </div>
        <div class={["message-content", @is_own_message && @status == :sent && "message-content--with-status"]}>
          <span class="message-text">
            <span
              :for={segment <- @segments}
              class={segment.kind == :mention && "message-mention"}
              data-mentioned-user-id={segment.mentioned_user_id}
            >{segment.text}</span>
          </span>
          <.delivery_status
            :if={@is_own_message && @status == :sent}
            msg={@msg}
            status={@message_status}
          />
        </div>
        <div
          :if={@is_own_message || @status in [:sending, :failed]}
          class="message-actions"
        >
          <%= if @is_own_message && @status == :sent do %>
            <details class="message-action-menu">
              <summary
                class="message-action-menu-trigger"
                aria-label="Mais ações da mensagem"
                title="Mais ações da mensagem"
              >
                <.icon name="carbon-overflow-menu-vertical" />
              </summary>
              <div class="message-action-menu-popover">
                <button
                  type="button"
                  class="message-action-edit"
                  phx-click="start_edit_message"
                  phx-value-message_id={@msg.id}
                >
                  <.icon name="carbon-edit" />
                  Editar mensagem
                </button>
                <%= if @deletable? do %>
                  <button
                    type="button"
                    class="message-action-delete"
                    phx-click="confirm_delete_message"
                    phx-value-message_id={@msg.id}
                  >
                    <.icon name="carbon-trash" />
                    Excluir mensagem
                  </button>
                <% else %>
                  <button
                    type="button"
                    class="message-action-delete"
                    disabled
                    aria-label="Mensagem já lida; não pode ser excluída"
                    title="Mensagem já lida; não pode ser excluída"
                  >
                    <.icon name="carbon-trash" />
                    Mensagem já lida; não pode ser excluída
                  </button>
                <% end %>
              </div>
            </details>
          <% end %>

          <%= if @status == :sending do %>
            <span class="message-delivery-status" role="status" aria-live="polite">Enviando…</span>
          <% end %>

          <%= if @status == :failed do %>
            <span
              class="message-delivery-status message-delivery-status--failed"
              role="status"
              aria-live="polite"
            >
              <.icon name="carbon-error" class="message-error-icon" />
              Falha no envio
            </span>
            <button
              type="button"
              class="message-retry"
              phx-click="retry_message"
              phx-value-message_id={@msg.id}
            >
              Tentar novamente
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Delivery status
  # ---------------------------------------------------------------------------

  attr :msg, :map, required: true
  attr :status, :atom, required: true

  def delivery_status(assigns) do
    ~H"""
    <%= case @status do %>
      <% :read -> %>
        <span
          class="message-delivery-status message-delivery-status--read"
          title={message_tooltip(@msg)}
          aria-label={message_status_label(:read, @msg)}
        >
          <span class="message-delivery-icon" aria-hidden="true">✓✓</span>
          <span class="message-delivery-label">Lida</span>
        </span>
      <% :delivered -> %>
        <span
          class="message-delivery-status message-delivery-status--delivered"
          title={message_tooltip(@msg)}
          aria-label={message_status_label(:delivered, @msg)}
        >
          <span class="message-delivery-icon" aria-hidden="true">✓✓</span>
          <span class="message-delivery-label">Entregue</span>
        </span>
      <% _ -> %>
        <span
          class="message-delivery-status message-delivery-status--sent"
          title={message_tooltip(@msg)}
          aria-label={message_status_label(:sent, @msg)}
        >
          <span class="message-delivery-icon" aria-hidden="true">✓</span>
          <span class="message-delivery-label">Enviada</span>
        </span>
    <% end %>
    """
  end

  defp message_tooltip(message) do
    reader_names = message.reader_names || []

    cond do
      reader_names != [] -> "Lida por: #{Enum.join(reader_names, ", ")}"
      message.delivered_count > 0 -> "Entregue a #{message.delivered_count} pessoa(s)"
      true -> "Enviada"
    end
  end

  defp message_status_label(:read, message), do: "Lida. #{message_tooltip(message)}"
  defp message_status_label(:delivered, message), do: "Entregue. #{message_tooltip(message)}"
  defp message_status_label(:sent, message), do: "Enviada. #{message_tooltip(message)}"

  defp message_deletable?(message, current_user_id) do
    message.user.id == current_user_id and Map.get(message, :reader_names, []) == []
  end

  defp message_edited_tooltip(edited_at) do
    "Editada às " <> ChatWeb.Time.format(edited_at, "%H:%M")
  end

  # ---------------------------------------------------------------------------
  # Pending message
  # ---------------------------------------------------------------------------

  attr :msg, :map, required: true
  attr :compact, :boolean, default: false

  def pending_message(assigns) do
    assigns = assign(assigns, :segments, message_segments(assigns.msg))

    ~H"""
    <div
      id={@msg.id}
      data-pending-message
      data-pending-client-id={@msg.client_id}
      class={"message message--user#{if @compact, do: " message--grouped", else: ""}"}
    >
      <div class="message-avatar-wrapper">
        <div class="message-avatar message-avatar--gray">
          <%= String.first(@msg.user.username) |> String.upcase() %>
        </div>

      </div>
      <div class="message-body">
        <div class="message-metadata">
          <span class="message-author">Você</span>
          <span class="message-time"><%= ChatWeb.Time.format(@msg.inserted_at, "%H:%M") %></span>
        </div>
        <div class="message-content">
          <span :for={segment <- @segments}>{segment.text}</span>
        </div>
        <div class="message-actions">
          <%= if @msg.status == :sending do %>
            <span class="message-delivery-status" role="status" aria-live="polite">Enviando…</span>
          <% end %>
          <%= if @msg.status == :failed do %>
            <span
              class="message-delivery-status message-delivery-status--failed"
              role="status"
              aria-live="polite"
            >
              <.icon name="carbon-error" class="message-error-icon" /> Falha no envio
            </span>
            <button
              type="button"
              class="message-retry"
              phx-click="retry_message"
              phx-value-message_id={@msg.id}
            >
              Tentar novamente
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Message form
  # ---------------------------------------------------------------------------

  attr :input_text, :string, required: true
  attr :mention_suggestions, :list, default: []
  attr :room_id, :string, required: true

  def message_form(assigns) do
    ~H"""
    <div
      id="message-outbox"
      class="chat-input"
    >
      <form
        id="message-form"
        phx-hook="MessageOutbox"
        data-outbox-storage-key={"chat:pending:#{@room_id}"}
        phx-submit="send_message"
        phx-change="update_input"
      >
        <.input type="textarea" name="text" value={@input_text}
                placeholder="Digite sua mensagem..." autocomplete="off"
                rows="1" maxlength="4000"
                aria-label="Mensagem"
                role="combobox" aria-autocomplete="list"
                aria-expanded={to_string(@mention_suggestions != [])}
                aria-controls="mention-suggestions"
                phx-debounce="0"
                phx-blur="stop_typing" />
        <span class="message-composer-hint">Enter envia · Shift+Enter quebra linha</span>
        <div
          :if={@mention_suggestions != []}
          id="mention-suggestions"
          class="mention-suggestions"
          role="listbox"
          aria-label="Sugestões de pessoas"
        >
          <button
            :for={user <- @mention_suggestions}
            id={"mention-option-#{user.id}"}
            type="button"
            tabindex="-1"
            role="option"
            aria-selected="false"
            class="mention-suggestion"
            phx-click="select_mention"
            phx-value-username={user.username}
          >
            <span class="mention-suggestion-avatar" aria-hidden="true">
              {user.username |> String.first() |> String.upcase()}
            </span>
            <span>@{user.username}</span>
          </button>
        </div>
        <button type="submit" class="btn btn-primary btn-send"
                aria-label="Enviar mensagem" title="Enviar mensagem">
          <.icon name="carbon-send-filled" />
        </button>
      </form>
    </div>
    """
  end

  defp message_segments(%{content: content} = message) when is_binary(content) do
    mentions =
      case Map.get(message, :mentions, []) do
        mentions when is_list(mentions) ->
          mentions
          |> Enum.filter(&valid_mention_shape?/1)
          |> Enum.sort_by(& &1.start_offset)

        _not_loaded ->
          []
      end

    {segments, cursor} =
      Enum.reduce(mentions, {[], 0}, fn mention, {segments, cursor} ->
        if valid_mention?(mention, content, cursor) do
          prefix_length = mention.start_offset - cursor
          segments = maybe_append_text(segments, content, cursor, prefix_length)
          mention_text = binary_part(content, mention.start_offset, mention.length)

          mention_segment = %{
            kind: :mention,
            text: mention_text,
            mentioned_user_id: Map.get(mention, :mentioned_user_id)
          }

          {segments ++ [mention_segment], mention.start_offset + mention.length}
        else
          {segments, cursor}
        end
      end)

    maybe_append_text(segments, content, cursor, byte_size(content) - cursor)
  end

  defp valid_mention_shape?(%{start_offset: start_offset, length: length}) do
    is_integer(start_offset) and is_integer(length)
  end

  defp valid_mention_shape?(_mention), do: false

  defp valid_mention?(mention, content, cursor) do
    mention.start_offset >= cursor and
      mention.length > 1 and
      mention.start_offset + mention.length <= byte_size(content) and
      binary_part(content, mention.start_offset, 1) == "@"
  end

  defp maybe_append_text(segments, _content, _offset, 0), do: segments

  defp maybe_append_text(segments, content, offset, length) do
    segments ++
      [
        %{
          kind: :text,
          text: binary_part(content, offset, length),
          mentioned_user_id: nil
        }
      ]
  end
end
