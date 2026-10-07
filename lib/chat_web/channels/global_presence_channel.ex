defmodule ChatWeb.GlobalPresenceChannel do
  @moduledoc "Tracks authenticated users on a process-wide online Presence topic."

  use ChatWeb, :channel

  alias ChatWeb.Presence

  @topic "presence:global"

  @impl true
  def join(@topic, _params, %{assigns: %{current_user: %{id: _id}}} = socket) do
    send(self(), :after_join)
    {:ok, %{}, socket}
  end

  def join(@topic, _params, _socket), do: {:error, %{reason: "forbidden"}}

  @impl true
  def handle_info(:after_join, socket) do
    user = socket.assigns.current_user
    {:ok, _} = Presence.track_online(socket, user)
    push(socket, "presence_state", Presence.list(@topic))
    {:noreply, socket}
  end
end
