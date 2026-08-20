defmodule ChatWeb.PubSubManager do
  @moduledoc """
  Gerencia inscrições PubSub das salas atribuídas ao usuário no socket.

  Inscrições individuais validam membership no banco. Inscrições em lote usam
  `socket.assigns.rooms`, que é carregado por `RoomNavigation` a partir da
  consulta autorizada de salas, para não repetir uma query por sala no mount.
  """

  require Logger

  alias Chat.Rooms

  @doc """
  Inscreve em uma sala específica após validar membership.
  """
  @spec subscribe(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def subscribe(socket, room) do
    user_id = socket.assigns.current_user.id

    cond do
      not Phoenix.LiveView.connected?(socket) ->
        Logger.debug("PubSub subscribe skipped: socket disconnected")
        socket

      not Rooms.room_member?(user_id, room.id) ->
        Logger.warning("PubSub subscribe blocked: user #{user_id} not member of room #{room.id}")
        socket

      true ->
        Logger.debug("PubSub subscribing user #{user_id} to room #{room.id}")
        do_subscribe(room.id)
        track_subscription(:subscribe, user_id, room.id)
        socket
    end
  end

  @doc """
  Cancela a inscrição no tópico de uma sala.
  """
  @spec unsubscribe(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def unsubscribe(socket, room_id) do
    if Phoenix.LiveView.connected?(socket) do
      user_id = socket.assigns.current_user.id

      Logger.debug("PubSub unsubscribing user #{user_id} from room #{room_id}")
      do_unsubscribe(room_id)
      track_subscription(:unsubscribe, user_id, room_id)
    end

    socket
  end

  @doc """
  Inscreve em todas as salas atribuídas ao socket sem consultas adicionais.
  """
  @spec subscribe_rooms(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def subscribe_rooms(socket) do
    if Phoenix.LiveView.connected?(socket) do
      user_id = socket.assigns.current_user.id
      room_ids = assigned_room_ids(socket)

      Logger.info("PubSub batch subscribing user #{user_id} to #{length(room_ids)} rooms")

      started_at = System.monotonic_time()
      Enum.each(room_ids, &do_subscribe/1)

      :telemetry.execute(
        [:chat, :pubsub, :batch_subscribe],
        %{count: length(room_ids), duration: System.monotonic_time() - started_at},
        %{user_id: user_id}
      )
    end

    socket
  end

  @doc """
  Cancela inscrição em múltiplas salas.
  """
  @spec unsubscribe_rooms(Phoenix.LiveView.Socket.t(), list(String.t())) ::
          Phoenix.LiveView.Socket.t()
  def unsubscribe_rooms(socket, room_ids) do
    if Phoenix.LiveView.connected?(socket) do
      user_id = socket.assigns.current_user.id

      Logger.info("PubSub batch unsubscribing user #{user_id} from #{length(room_ids)} rooms")
      Enum.each(room_ids, &do_unsubscribe/1)
    end

    socket
  end

  defp assigned_room_ids(socket) do
    socket.assigns[:rooms]
    |> List.wrap()
    |> Enum.map(& &1.id)
  end

  defp do_subscribe(room_id), do: Phoenix.PubSub.subscribe(Chat.PubSub, room_topic(room_id))
  defp do_unsubscribe(room_id), do: Phoenix.PubSub.unsubscribe(Chat.PubSub, room_topic(room_id))

  defp track_subscription(action, user_id, room_id) do
    :telemetry.execute([:chat, :pubsub, action], %{}, %{user_id: user_id, room_id: room_id})
  end

  defp room_topic(room_id), do: "room:#{room_id}"
end
