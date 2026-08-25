defmodule ChatWeb.TreatmentQueueChannel do
  @moduledoc "Realtime updates for the logistics treatment queue."

  use ChatWeb, :channel

  @impl true
  def join(
        "treatments:queue",
        _params,
        %{assigns: %{current_user: %{role: "logistics_agent"}}} = socket
      ) do
    {:ok, %{}, socket}
  end

  def join("treatments:queue", _params, _socket), do: {:error, %{reason: "forbidden"}}

  @impl true
  def handle_out(event, payload, socket) do
    {:noreply, push(socket, event, payload)}
  end
end
