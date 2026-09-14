defmodule ChatWeb.UserChannel do
  @moduledoc "Private realtime notifications for the authenticated user."

  use ChatWeb, :channel

  @impl true
  def join("user:" <> user_id, _params, %{assigns: %{current_user: %{id: user_id}}} = socket) do
    {:ok, %{}, socket}
  end

  def join("user:" <> _user_id, _params, _socket), do: {:error, %{reason: "forbidden"}}

  @impl true
  def handle_info({:assigned_room_message_created, payload}, socket) do
    push(socket, "room:message:new", payload)
    {:noreply, socket}
  end

  def handle_info({:mention_created, payload}, socket) do
    push(socket, "mention:created", payload)
    {:noreply, socket}
  end

  def handle_info({:mention_deleted, payload}, socket) do
    push(socket, "mention:deleted", payload)
    {:noreply, socket}
  end

  def handle_info({:mention_state_changed, payload}, socket) do
    push(socket, "mention:state_changed", payload)
    {:noreply, socket}
  end

  def handle_info({:treatment_assigned, payload}, socket) do
    push(socket, "treatment:assigned", payload)
    {:noreply, socket}
  end

  @impl true
  def handle_out(event, payload, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end
end
