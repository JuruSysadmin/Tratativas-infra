defmodule ChatWeb.RoomChannel do
  @moduledoc "Phoenix Channel transport for room messages and presence events."

  use ChatWeb, :channel

  alias Chat.Accounts
  alias Chat.Messages
  alias Chat.Messages.Attachments
  alias Chat.Repo
  alias Chat.Rooms
  alias Chat.Treatments
  alias Chat.Treatments.Treatment
  alias ChatWeb.Presence

  @impl true
  def join("room:" <> room_id, _params, socket) do
    user = socket.assigns.current_user

    if Rooms.room_member?(user.id, room_id) do
      send(self(), :after_join)
      {:ok, %{room_id: room_id}, assign(socket, :room_id, room_id)}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    user = socket.assigns.current_user
    room_id = socket.assigns.room_id
    {:ok, _} = Presence.track_user(socket, user)

    broadcast!(socket, "user:joined", %{
      user_id: user.id,
      username: user.username
    })

    online_users = Presence.list_online_users("room:#{room_id}")
    push(socket, "presence_state", %{users: online_users})

    {:noreply, socket}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    {:noreply, socket}
  end

  def handle_info({:message_deleted, room_id, message_id}, socket) do
    if socket.assigns.room_id == room_id do
      push(socket, "message:deleted", %{message_id: message_id})
    end

    {:noreply, socket}
  end

  def handle_info({:message_created, message}, socket) do
    push(socket, "message:new", message_payload(message))
    {:noreply, socket}
  end

  def handle_info({:message_updated, message}, socket) do
    if socket.assigns.room_id == message.room_id do
      push(socket, "message:updated", message_payload(message))
    end

    {:noreply, socket}
  end

  def handle_info(
        {:read_receipts_updated, room_id, user_id, message_ids},
        %{assigns: %{room_id: room_id}} = socket
      ) do
    push(socket, "read_receipts:updated", %{user_id: user_id, message_ids: message_ids})
    {:noreply, socket}
  end

  def handle_info({:read_receipts_updated, _room_id, _user_id, _message_ids}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_in(
        "message:new",
        %{"content" => content, "client_id" => client_id} = params,
        socket
      )
      when is_binary(content) and is_binary(client_id) do
    user = socket.assigns.current_user
    room_id = socket.assigns.room_id

    attrs = %{"content" => content}
    attachment_ids = Map.get(params, "attachment_ids", [])

    case Messages.create_message(attrs, user.id, room_id,
           client_id: client_id,
           attachment_ids: attachment_ids
         ) do
      {:ok, _message} ->
        {:reply, :ok, socket}

      {:error, :invalid_client_id} ->
        {:reply, {:error, %{reason: "invalid_client_id"}}, socket}

      {:error, :invalid_attachments} ->
        {:reply, {:error, %{reason: "invalid_attachments"}}, socket}

      {:error, _changeset} ->
        {:reply, {:error, %{reason: "invalid_message"}}, socket}
    end
  end

  def handle_in("message:new", _params, socket) do
    {:reply, {:error, %{reason: "invalid_message"}}, socket}
  end

  def handle_in("message:delete", %{"message_id" => message_id}, socket) do
    user = socket.assigns.current_user

    case Messages.delete_own_unread_message(message_id, user.id, socket.assigns.room_id) do
      {:ok, _message} ->
        {:reply, :ok, socket}

      {:error, reason} when reason in [:not_found, :not_member, :not_authorized] ->
        {:reply, {:error, %{reason: Atom.to_string(reason)}}, socket}

      {:error, :already_read} ->
        {:reply, {:error, %{reason: "already_read"}}, socket}

      {:error, _changeset} ->
        {:reply, {:error, %{reason: "delete_failed"}}, socket}
    end
  end

  def handle_in("message:edit", %{"message_id" => message_id, "content" => content}, socket)
      when is_binary(message_id) and is_binary(content) do
    user = socket.assigns.current_user

    case Messages.edit_own_message(message_id, user.id, socket.assigns.room_id, %{
           "content" => content
         }) do
      {:ok, _message} ->
        {:reply, :ok, socket}

      {:error, reason} when reason in [:not_found, :not_member, :not_authorized] ->
        {:reply, {:error, %{reason: Atom.to_string(reason)}}, socket}

      {:error, %Ecto.Changeset{}} ->
        {:reply, {:error, %{reason: "invalid_message"}}, socket}

      {:error, _reason} ->
        {:reply, {:error, %{reason: "message_edit_failed"}}, socket}
    end
  end

  def handle_in("message:edit", _params, socket) do
    {:reply, {:error, %{reason: "invalid_message"}}, socket}
  end

  def handle_in("treatment:assign_to_me", _params, socket) do
    case Repo.get_by(Treatment, room_id: socket.assigns.room_id) do
      nil ->
        {:reply, {:error, %{reason: "not_found"}}, socket}

      treatment ->
        case Treatments.assign_agent(treatment, socket.assigns.current_user) do
          {:ok, assigned_treatment} ->
            payload = treatment_assignment_payload(assigned_treatment)

            maybe_broadcast_treatment_assignment(socket, treatment, payload)

            {:reply, {:ok, payload}, socket}

          {:error, reason} when reason in [:forbidden, :already_assigned, :not_found] ->
            {:reply, {:error, %{reason: Atom.to_string(reason)}}, socket}
        end
    end
  end

  def handle_in("typing:start", _params, socket) do
    Presence.update_typing(socket, socket.assigns.current_user, true)
    {:noreply, socket}
  end

  def handle_in("typing:stop", _params, socket) do
    Presence.update_typing(socket, socket.assigns.current_user, false)
    {:noreply, socket}
  end

  def handle_in("user:status", %{"status" => status}, socket) do
    user = socket.assigns.current_user

    case Accounts.update_user(user, %{status: status}) do
      {:ok, updated_user} ->
        broadcast!(socket, "user:status", %{
          user_id: updated_user.id,
          status: updated_user.status
        })

        {:noreply, assign(socket, :current_user, updated_user)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  defp message_payload(message) do
    %{
      id: message.id,
      content: message.content,
      user: %{
        id: message.user.id,
        username: message.user.username
      },
      room_id: message.room_id,
      inserted_at: message.inserted_at,
      edited_at: message.edited_at,
      attachments: Attachments.message_payload_attachments(message)
    }
  end

  defp treatment_assignment_payload(treatment) do
    %{
      treatment_id: treatment.id,
      assigned_agent_id: treatment.assigned_agent_id,
      assigned_at: treatment.assigned_at
    }
  end

  defp maybe_broadcast_treatment_assignment(
         socket,
         %Treatment{assigned_agent_id: nil},
         payload
       ) do
    broadcast!(socket, "treatment:agent_assigned", payload)
  end

  defp maybe_broadcast_treatment_assignment(_socket, %Treatment{}, _payload), do: :ok
end
