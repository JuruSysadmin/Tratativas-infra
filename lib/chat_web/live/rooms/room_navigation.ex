defmodule ChatWeb.RoomNavigation do
  @moduledoc """
  Gerencia os assigns de interface relacionados à navegação de salas.

  Carrega somente salas atribuídas ao usuário atual e mantém a lista e as
  contagens não lidas sincronizadas.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Chat.Rooms

  @max_search_length 100

  @doc """
  Inicializa os assigns de navegação, unread e subscriptions do socket.
  """
  def init(socket) do
    socket
    |> assign(:rooms, [])
    |> assign(:current_room, nil)
    |> assign(:room_dialog, nil)
    |> assign(:pending_room, nil)
    |> assign(:available_rooms, [])
    |> assign(:room_search, "")
    |> assign(:navigation_open, false)
    |> reload_user_rooms()
    |> ChatWeb.PubSubManager.subscribe_rooms()
  end

  @doc """
  Recarrega salas atribuídas e suas contagens não lidas.
  """
  def refresh(socket) do
    reload_user_rooms(socket)
  end

  @doc """
  Abre o diálogo de criação de sala.
  """
  def open_new_dialog(socket) do
    assign(socket, :room_dialog, :new)
  end

  @doc """
  Abre o explorador de salas disponíveis.
  """
  def open_explorer(socket) do
    socket
    |> load_available_rooms("")
    |> assign(:room_dialog, :explore)
  end

  @doc """
  Fecha o diálogo de salas e limpa seu estado transitório.
  """
  def close_dialog(socket) do
    socket
    |> assign(:room_dialog, nil)
    |> assign(:room_search, "")
    |> assign(:pending_room, nil)
  end

  @doc """
  Busca salas disponíveis para o usuário atual.
  """
  def search_available(socket, query) when byte_size(query) <= @max_search_length do
    load_available_rooms(socket, query)
  end

  def search_available(socket, _query), do: socket

  @doc """
  Limpa a busca de salas disponíveis.
  """
  def clear_search(socket) do
    load_available_rooms(socket, "")
  end

  @doc """
  Encontra uma sala já atribuída no estado do socket.
  """
  def find_assigned_room(socket, room_id) do
    Enum.find(socket.assigns[:rooms] || [], &(&1.id == room_id))
  end

  defp reload_user_rooms(socket) do
    rooms = Rooms.get_user_rooms(socket.assigns.current_user.id)

    socket
    |> assign(:rooms, rooms)
    |> ChatWeb.UnreadTracking.reload(rooms)
  end

  defp load_available_rooms(socket, query) do
    available_rooms = Rooms.list_available_rooms(socket.assigns.current_user.id, query)

    socket
    |> assign(:available_rooms, available_rooms)
    |> assign(:room_search, query)
  end
end
