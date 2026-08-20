defmodule ChatWeb.ChatLive do
  @moduledoc """
  LiveView principal do chat.

  Delega gerenciamento de estado para ChatState, ChatMessages, ChatPresence
  e RoomNavigation, mantendo os handlers focados apenas na orquestração de eventos.
  """

  use ChatWeb, :live_view

  alias Chat.Messages
  alias Chat.Messages.MentionParser
  alias Chat.Rooms
  alias ChatWeb.ChatMessages
  alias ChatWeb.ChatNotifications
  alias ChatWeb.ChatPresence
  alias ChatWeb.ChatState
  alias ChatWeb.RoomManagement
  alias ChatWeb.RoomNavigation
  alias ChatWeb.TypingManager
  alias ChatWeb.UnreadTracking

  @active_mention_regex ~r/(?:^|[^\p{L}\p{N}_@])@([\p{L}\p{N}._-]*)$/u

  @impl true
  def mount(_params, _session, socket) do
    socket = ChatState.init(socket)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Chat.PubSub, "user:#{socket.assigns.current_user.id}")
    end

    {:ok, socket}
  end

  @impl true
  def handle_event("select_room", %{"room_id" => room_id}, socket) do
    case RoomNavigation.find_assigned_room(socket, room_id) do
      %{} = room ->
        socket =
          socket
          |> ChatState.select_room(room)

        if selected_room?(socket, room.id) && connected?(socket) do
          {:noreply, push_patch(socket, to: ~p"/chat?room_id=#{room.id}")}
        else
          {:noreply, socket}
        end

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_notification_panel", _params, socket) do
    {:noreply, ChatNotifications.toggle_panel(socket)}
  end

  def handle_event("close_notification_panel", _params, socket) do
    {:noreply, ChatNotifications.close_panel(socket)}
  end

  def handle_event("dismiss_mention_notification", _params, socket) do
    {:noreply, ChatNotifications.dismiss_toast(socket)}
  end

  def handle_event("open_notification", %{"message_id" => message_id}, socket)
      when is_binary(message_id) do
    user_id = socket.assigns.current_user.id

    case Messages.get_mention_notification(user_id, message_id) do
      {:ok, %{message: %{room: room}}} ->
        socket =
          socket
          |> ChatState.select_room(room, through: message_id)
          |> ChatNotifications.close_panel()

        if selected_room?(socket, room.id) && connected?(socket) do
          {:noreply,
           socket
           |> push_patch(to: ~p"/chat?room_id=#{room.id}")
           |> push_event("scroll_to_message", %{id: "messages-#{message_id}"})}
        else
          {:noreply, socket}
        end

      _reason ->
        {:noreply,
         socket
         |> ChatNotifications.refresh()
         |> ChatNotifications.close_panel()}
    end
  end

  def handle_event("open_notification", _params, socket), do: {:noreply, socket}

  def handle_event("send_message", %{"client_id" => client_id, "text" => text}, socket)
      when is_binary(text) and text != "" do
    case Ecto.UUID.cast(client_id) do
      {:ok, client_id} -> {:noreply, queue_message(socket, text, client_id)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("send_message", %{"text" => text}, socket)
      when is_binary(text) and text != "" do
    {:noreply, queue_message(socket, text)}
  end

  def handle_event("send_message", _params, socket), do: {:noreply, socket}

  def handle_event("retry_message", %{"message_id" => message_id}, socket) do
    case socket.assigns.pending_messages do
      %{^message_id => %{status: :failed} = message} ->
        send(self(), {:persist_message, message.id, message.content, message.room_id})
        {:noreply, ChatMessages.update_pending_status(socket, message.id, :sending)}

      _pending_messages ->
        {:noreply, socket}
    end
  end

  def handle_event("restore_pending_messages", %{"messages" => messages}, socket)
      when is_list(messages) do
    if socket.assigns.pending_messages == %{} and socket.assigns.current_room do
      restored_messages =
        messages
        |> Enum.filter(&valid_restored_pending_message?/1)
        |> Enum.map(fn %{"client_id" => client_id, "content" => content} ->
          pending_message =
            ChatMessages.pending_message(
              content,
              socket.assigns.current_user,
              socket.assigns.current_room,
              client_id
            )

          send(
            self(),
            {:persist_message, pending_message.id, pending_message.content,
             pending_message.room_id}
          )

          pending_message
        end)

      socket =
        Enum.reduce(restored_messages, socket, fn message, socket ->
          put_pending_message(socket, message)
        end)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("restore_pending_messages", _params, socket), do: {:noreply, socket}

  def handle_event("update_input", %{"text" => text}, socket) when is_binary(text) do
    socket =
      socket
      |> assign(:input_text, text)
      |> assign(:mention_suggestions, mention_suggestions(socket, text))
      |> maybe_update_typing(text)

    {:noreply, socket}
  end

  def handle_event("update_input", _params, socket), do: {:noreply, socket}

  def handle_event("dismiss_mentions", _params, socket) do
    {:noreply, assign(socket, :mention_suggestions, [])}
  end

  def handle_event("select_mention", %{"username" => username}, socket)
      when is_binary(username) do
    selected_user =
      Enum.find(socket.assigns.mention_suggestions, &(&1.username == username))

    case {selected_user, active_mention(socket.assigns.input_text)} do
      {%{} = user, {:ok, _query, start_offset}} ->
        prefix = binary_part(socket.assigns.input_text, 0, start_offset)

        {:noreply,
         socket
         |> assign(:input_text, prefix <> MentionParser.format(user.username) <> " ")
         |> assign(:mention_suggestions, [])}

      _invalid_or_stale_selection ->
        {:noreply, socket}
    end
  end

  def handle_event("select_mention", _params, socket), do: {:noreply, socket}

  def handle_event("stop_typing", _params, socket) do
    {:noreply, TypingManager.stop_typing(socket)}
  end

  def handle_event("mark_read", %{"message_ids" => message_ids}, socket)
      when is_list(message_ids) do
    {inserted_ids, position_advanced?} = ChatMessages.mark_read(socket, message_ids)
    room = socket.assigns.current_room
    user = socket.assigns.current_user

    case {room, inserted_ids} do
      {%{id: room_id}, [_message_id | _message_ids]} ->
        Chat.Broadcaster.broadcast_read_receipts_updated(room_id, user.id, inserted_ids)

      {_room, []} ->
        :ok
    end

    socket =
      case {room, position_advanced?} do
        {%{id: room_id}, true} ->
          Chat.Broadcaster.broadcast_mention_state_changed(user.id, room_id)

          socket
          |> UnreadTracking.refresh(room_id)
          |> ChatState.refresh_mentions()

        {_room, false} ->
          socket
      end

    {:noreply, socket}
  end

  def handle_event("mark_read", _params, socket), do: {:noreply, socket}

  def handle_event("mark_delivered", %{"message_ids" => message_ids}, socket)
      when is_list(message_ids) do
    {delivered_ids, position_advanced?} = ChatMessages.mark_delivered(socket, message_ids)

    case {socket.assigns.current_room, position_advanced?} do
      {%{id: room_id}, true} ->
        Chat.Broadcaster.broadcast_delivery_receipts_updated(
          room_id,
          socket.assigns.current_user.id,
          delivered_ids
        )

      {_room, false} ->
        :ok
    end

    {:noreply, socket}
  end

  def handle_event("mark_delivered", _params, socket), do: {:noreply, socket}

  def handle_event("load_older_messages", _params, socket) do
    case socket.assigns.oldest_message_id do
      oldest_id when not is_nil(oldest_id) ->
        {:noreply, ChatMessages.load_older(socket, oldest_id)}

      nil ->
        {:noreply, assign(socket, :has_more_messages, false)}
    end
  end

  def handle_event("confirm_delete_message", %{"message_id" => message_id}, socket)
      when is_binary(message_id) do
    socket =
      case Ecto.UUID.cast(message_id) do
        {:ok, _message_id} -> assign(socket, :pending_message_deletion_id, message_id)
        :error -> socket
      end

    {:noreply, socket}
  end

  def handle_event("confirm_delete_message", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_delete_message", _params, socket) do
    {:noreply, assign(socket, :pending_message_deletion_id, nil)}
  end

  def handle_event("delete_message", %{"message_id" => message_id}, socket) do
    user = socket.assigns.current_user
    room = socket.assigns.current_room

    with %{id: room_id} <- room,
         {:ok, message} <- Messages.delete_own_unread_message(message_id, user.id, room_id) do
      {:noreply,
       socket
       |> ChatMessages.remove(message.id)
       |> assign(:pending_message_deletion_id, nil)}
    else
      {:error, :already_read} ->
        {:noreply,
         socket
         |> put_flash(:error, "Mensagem já foi lida e não pode ser deletada")
         |> assign(:pending_message_deletion_id, nil)}

      {:error, _reason} ->
        {:noreply, assign(socket, :pending_message_deletion_id, nil)}

      nil ->
        {:noreply, assign(socket, :pending_message_deletion_id, nil)}
    end
  end

  def handle_event("start_edit_message", %{"message_id" => message_id}, socket)
      when is_binary(message_id) do
    socket =
      case Ecto.UUID.cast(message_id) do
        {:ok, _message_id} ->
          case Map.get(socket.assigns.message_map, message_id) do
            %{user: %{id: user_id}, content: content}
            when user_id == socket.assigns.current_user.id ->
              socket
              |> assign(:editing_message_id, message_id)
              |> assign(:editing_content, content)

            _not_editable ->
              socket
          end

        :error ->
          socket
      end

    {:noreply, socket}
  end

  def handle_event("start_edit_message", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_edit_message", _params, socket) do
    {:noreply, close_edit_dialog(socket)}
  end

  def handle_event("update_edit_content", %{"value" => content}, socket)
      when is_binary(content) do
    {:noreply, assign(socket, :editing_content, content)}
  end

  def handle_event("update_edit_content", %{"content" => content}, socket)
      when is_binary(content) do
    {:noreply, assign(socket, :editing_content, content)}
  end

  def handle_event("update_edit_content", _params, socket), do: {:noreply, socket}

  def handle_event("save_edit_message", %{"message_id" => message_id} = params, socket)
      when is_binary(message_id) do
    user = socket.assigns.current_user
    room = socket.assigns.current_room

    content =
      Map.get(
        params,
        "value",
        Map.get(params, "content", Map.get(socket.assigns, :editing_content, ""))
      )

    with %{id: room_id} <- room,
         {:ok, message} <-
           Messages.edit_own_message(message_id, user.id, room_id, %{"content" => content}) do
      {:noreply,
       socket
       |> ChatMessages.update_message(message)
       |> close_edit_dialog()}
    else
      {:error, _reason} -> {:noreply, close_edit_dialog(socket)}
      nil -> {:noreply, close_edit_dialog(socket)}
    end
  end

  def handle_event("save_edit_message", _params, socket), do: {:noreply, socket}

  def handle_event("toggle_navigation", _params, socket) do
    {:noreply, update(socket, :navigation_open, &(!&1))}
  end

  def handle_event("pin_room", %{"room_id" => room_id}, socket) do
    case Rooms.pin_room(socket.assigns.current_user.id, room_id) do
      {:ok, _membership} -> {:noreply, RoomNavigation.refresh(socket)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  def handle_event("unpin_room", %{"room_id" => room_id}, socket) do
    case Rooms.unpin_room(socket.assigns.current_user.id, room_id) do
      {:ok, _membership} -> {:noreply, RoomNavigation.refresh(socket)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  def handle_event("pin_room", _params, socket), do: {:noreply, socket}
  def handle_event("unpin_room", _params, socket), do: {:noreply, socket}

  def handle_event("open_new_room", _params, socket) do
    {:noreply, RoomNavigation.open_new_dialog(socket)}
  end

  def handle_event("open_room_explorer", _params, socket) do
    {:noreply, RoomNavigation.open_explorer(socket)}
  end

  def handle_event("search_rooms", %{"query" => query}, socket) when is_binary(query) do
    {:noreply, RoomNavigation.search_available(socket, query)}
  end

  def handle_event("search_rooms", _params, socket), do: {:noreply, socket}

  def handle_event("clear_room_search", _params, socket) do
    {:noreply, RoomNavigation.clear_search(socket)}
  end

  def handle_event("close_room_dialog", _params, socket) do
    {:noreply, RoomNavigation.close_dialog(socket)}
  end

  def handle_event(
        "create_room",
        %{"room" => room_params},
        %{assigns: %{room_dialog: :new}} = socket
      ) do
    user = socket.assigns.current_user

    case RoomManagement.create(socket, room_params, user.id) do
      {:ok, socket} ->
        {:noreply, socket}

      {:error, reason, socket} ->
        {:noreply, put_flash(socket, :error, room_error_message(reason, :create))}
    end
  end

  def handle_event("create_room", _params, socket), do: {:noreply, socket}

  def handle_event(
        "join_room",
        %{"room_id" => room_id},
        %{assigns: %{room_dialog: :explore}} = socket
      ) do
    user = socket.assigns.current_user

    case RoomManagement.join(socket, room_id, user.id) do
      {:ok, socket} ->
        {:noreply, socket}

      {:error, reason, socket} ->
        {:noreply, put_flash(socket, :error, room_error_message(reason, :join))}
    end
  end

  def handle_event("join_room", _params, socket), do: {:noreply, socket}

  def handle_event("leave_room", %{"room_id" => room_id}, socket) do
    user = socket.assigns.current_user

    case RoomManagement.leave(socket, room_id, user.id) do
      {:ok, socket} ->
        {:noreply, socket}

      {:error, reason, socket} ->
        {:noreply, put_flash(socket, :error, room_error_message(reason, :leave))}
    end
  end

  def handle_event("confirm_delete_room", %{"room_id" => room_id}, socket) do
    user = socket.assigns.current_user

    case RoomManagement.confirm_delete(socket, room_id, user.id) do
      {:ok, room} ->
        {:noreply,
         socket
         |> assign(:pending_room, room)
         |> assign(:room_dialog, :delete)}

      {:error, :not_authorized} ->
        {:noreply, put_flash(socket, :error, "Você não pode excluir esta sala")}
    end
  end

  def handle_event("delete_room", %{"room_id" => room_id}, socket) do
    user = socket.assigns.current_user

    case RoomManagement.delete(socket, room_id, user.id) do
      {:ok, socket} ->
        {:noreply, socket}

      {:error, reason, socket} ->
        {:noreply, put_flash(socket, :error, room_error_message(reason, :delete))}
    end
  end

  defp queue_message(socket, text, client_id \\ Ecto.UUID.generate()) do
    room = socket.assigns.current_room
    user = socket.assigns.current_user

    if room && Rooms.room_member?(user.id, room.id) do
      pending_message = ChatMessages.pending_message(text, user, room, client_id)
      send(self(), {:persist_message, pending_message.id, text, room.id})

      socket
      |> put_pending_message(pending_message)
      |> push_event("scroll_to_bottom", %{})
      |> assign(:input_text, "")
      |> assign(:mention_suggestions, [])
      |> TypingManager.stop_typing()
    else
      socket
    end
  end

  @impl true
  def handle_params(%{"room_id" => room_id}, _uri, socket) do
    current_room = socket.assigns.current_room

    if current_room && current_room.id == room_id do
      {:noreply, socket}
    else
      case RoomNavigation.find_assigned_room(socket, room_id) do
        %{} = room -> {:noreply, ChatState.select_room(socket, room)}
        nil -> {:noreply, socket}
      end
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:persist_message, pending_id, text, room_id}, socket) do
    user = socket.assigns.current_user
    client_id = get_in(socket.assigns.pending_messages, [pending_id, :client_id])

    result =
      if Rooms.room_member?(user.id, room_id) do
        Messages.create_message(%{"content" => text}, user.id, room_id, client_id: client_id)
      else
        {:error, :forbidden}
      end

    case result do
      {:ok, message} ->
        {:noreply,
         socket
         |> ChatMessages.append_persisted(pending_id, message)
         |> UnreadTracking.clear(room_id)}

      {:error, _reason} ->
        {:noreply, ChatMessages.update_pending_status(socket, pending_id, :failed)}
    end
  end

  def handle_info({:message_created, message}, socket) do
    case Rooms.fetch_member_room(socket.assigns.current_user.id, message.room_id) do
      {:ok, _room} ->
        socket =
          if message.user_id == socket.assigns.current_user.id do
            socket
          else
            push_event(socket, "play_notification_sound", %{room_id: message.room_id})
          end

        cond do
          selected_room?(socket, message.room_id) ->
            {:noreply, ChatMessages.append_persisted(socket, nil, message)}

          message.user_id == socket.assigns.current_user.id ->
            {:noreply, socket}

          true ->
            {:noreply, UnreadTracking.increment(socket, message.room_id)}
        end

      {:error, _reason} ->
        {:noreply, ChatState.revoke_room_access(socket, message.room_id)}
    end
  end

  def handle_info({:message_deleted, room_id, message_id}, socket) do
    case authorize_room_event(socket, room_id) do
      {:ok, socket} ->
        socket = UnreadTracking.refresh(socket, room_id)

        if selected_room?(socket, room_id) do
          {:noreply, ChatMessages.remove(socket, message_id)}
        else
          {:noreply, socket}
        end

      {:error, socket} ->
        {:noreply, socket}
    end
  end

  def handle_info({:message_updated, message}, socket) do
    case authorize_room_event(socket, message.room_id) do
      {:ok, socket} ->
        socket =
          if selected_room?(socket, message.room_id) do
            ChatMessages.update_message(socket, message)
          else
            socket
          end

        {:noreply, socket}

      {:error, socket} ->
        {:noreply, socket}
    end
  end

  def handle_info({:read_receipts_updated, room_id, reader_id, message_ids}, socket) do
    case authorize_room_event(socket, room_id) do
      {:ok, socket} ->
        socket =
          if reader_id == socket.assigns.current_user.id do
            socket
            |> UnreadTracking.refresh(room_id)
            |> ChatState.refresh_mentions()
          else
            socket
          end

        socket =
          if selected_room?(socket, room_id) do
            ChatMessages.refresh_read_counts(socket, message_ids)
          else
            socket
          end

        {:noreply, socket}

      {:error, socket} ->
        {:noreply, socket}
    end
  end

  def handle_info({:delivery_receipts_updated, room_id, _recipient_id, _message_ids}, socket) do
    case authorize_room_event(socket, room_id) do
      {:ok, socket} ->
        socket =
          if selected_room?(socket, room_id) do
            socket
            |> ChatMessages.refresh_counts()
            |> ChatMessages.refresh_statuses()
          else
            socket
          end

        {:noreply, socket}

      {:error, socket} ->
        {:noreply, socket}
    end
  end

  def handle_info({:mention_created, %{message_id: message_id, room_id: room_id}}, socket) do
    socket = ChatState.refresh_mentions(socket)

    if selected_room?(socket, room_id) do
      {:noreply, socket}
    else
      {:noreply, ChatNotifications.show_toast(socket, message_id)}
    end
  end

  def handle_info({:mention_deleted, _payload}, socket) do
    {:noreply, ChatState.refresh_mentions(socket)}
  end

  def handle_info({:mention_state_changed, _payload}, socket) do
    {:noreply, ChatState.refresh_mentions(socket)}
  end

  def handle_info({:membership_left, %{room_id: room_id}}, socket) do
    {:noreply, ChatState.revoke_room_access(socket, room_id)}
  end

  def handle_info({:room_deleted, %{room_id: room_id}}, socket) do
    {:noreply, ChatState.revoke_room_access(socket, room_id)}
  end

  def handle_info(
        %Phoenix.Socket.Broadcast{topic: topic, event: "presence_diff"},
        %{assigns: %{current_room: %{id: room_id}}} = socket
      ) do
    if topic == room_topic(room_id) do
      case authorize_room_event(socket, room_id) do
        {:ok, socket} ->
          previous_users = socket.assigns.online_users

          socket =
            socket
            |> ChatPresence.refresh_online_users()
            |> ChatMessages.refresh_statuses()
            |> TypingManager.refresh()

          {:noreply,
           ChatPresence.reconcile(socket, previous_users, socket.assigns.online_users, room_id)}

        {:error, socket} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info({:confirm_presence_leave, room_id, user_id, timer_token}, socket) do
    {:noreply, ChatPresence.confirm_leave(socket, room_id, user_id, timer_token)}
  end

  def handle_info({:dismiss_status, id}, socket) do
    {:noreply, ChatPresence.dismiss_status(socket, id)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  defp maybe_update_typing(socket, text) do
    if socket.assigns.current_room do
      TypingManager.update_typing(socket, String.trim(text) != "")
    else
      socket
    end
  end

  defp mention_suggestions(%{assigns: %{current_room: nil}}, _text), do: []

  defp mention_suggestions(socket, text) do
    case active_mention(text) do
      {:ok, query, _start_offset} ->
        Rooms.search_room_members(
          socket.assigns.current_room.id,
          query,
          socket.assigns.current_user.id,
          exclude_user_id: socket.assigns.current_user.id,
          limit: 8
        )

      :none ->
        []
    end
  end

  defp active_mention(text) when is_binary(text) do
    case Regex.run(@active_mention_regex, text, capture: :all_but_first) do
      [query] -> {:ok, query, byte_size(text) - byte_size(query) - 1}
      nil -> :none
    end
  end

  defp put_pending_message(socket, message) do
    pending_order = socket.assigns[:pending_message_order] || []

    socket
    |> update(:pending_messages, &Map.put(&1, message.id, message))
    |> assign(:pending_message_order, pending_order ++ [message.id])
  end

  defp close_edit_dialog(socket) do
    socket
    |> assign(:editing_message_id, nil)
    |> assign(:editing_content, "")
  end

  defp valid_restored_pending_message?(%{"client_id" => client_id, "content" => content})
       when is_binary(content) and byte_size(content) > 0 and byte_size(content) <= 50_000 do
    match?({:ok, _uuid}, Ecto.UUID.cast(client_id))
  end

  defp valid_restored_pending_message?(_message), do: false

  defp selected_room?(socket, room_id) do
    socket.assigns.current_room && socket.assigns.current_room.id == room_id
  end

  defp authorize_room_event(socket, room_id) do
    case Rooms.fetch_member_room(socket.assigns.current_user.id, room_id) do
      {:ok, _room} -> {:ok, socket}
      {:error, _reason} -> {:error, ChatState.revoke_room_access(socket, room_id)}
    end
  end

  defp room_error_message(:not_found, _action), do: "Sala não encontrada"
  defp room_error_message(:not_authorized, _action), do: "Você não tem permissão para esta sala"
  defp room_error_message(:not_member, _action), do: "Você não participa desta sala"
  defp room_error_message(:creator_cannot_leave, :leave), do: "O criador não pode sair da sala"
  defp room_error_message(nil, _action), do: "Erro inesperado"
  defp room_error_message(_reason, :create), do: "Não foi possível criar a sala"
  defp room_error_message(_reason, :join), do: "Não foi possível entrar na sala"
  defp room_error_message(_reason, :leave), do: "Não foi possível sair da sala"
  defp room_error_message(_reason, :delete), do: "Não foi possível excluir a sala"

  defp room_topic(room_id), do: "room:#{room_id}"
end
