defmodule ChatWeb.RoomManagement do
  @moduledoc """
  Orquestra operações de criação, entrada, saída e exclusão de salas.

  As mutações retornam `{:ok, socket}` em sucesso ou
  `{:error, reason, socket}` em falha, mantendo o socket original nos erros.
  """

  import Phoenix.Component, only: [assign: 3]

  require OK

  alias Chat.Repo
  alias Chat.Rooms
  alias ChatWeb.ChatState
  alias ChatWeb.PubSubManager
  alias ChatWeb.RoomNavigation

  @doc """
  Cria uma sala e atualiza o socket para selecioná-la.
  """
  def create(socket, room_params, user_id) do
    OK.for do
      room <- Rooms.create_room(room_params, user_id)
      enriched_room = preload_room(room)
    after
      transition_after_create(socket, enriched_room)
    end
    |> with_original_socket(socket)
  end

  @doc """
  Associa o usuário a uma sala existente e a seleciona.
  """
  def join(socket, room_id, user_id) do
    OK.for do
      room <- find_room(room_id)
      _membership <- Rooms.join_room(user_id, room_id)
      enriched_room = preload_room(room)
    after
      transition_after_join(socket, enriched_room)
    end
    |> with_original_socket(socket)
  end

  @doc """
  Remove o usuário de uma sala e limpa o estado correspondente.
  """
  def leave(socket, room_id, user_id) do
    OK.for do
      _count <- Rooms.leave_room(user_id, room_id)
    after
      transition_after_leave(socket, room_id)
    end
    |> with_original_socket(socket)
  end

  @doc """
  Retorna a sala somente quando o usuário é seu criador.
  """
  def confirm_delete(_socket, room_id, user_id) do
    authorize_room_owner(room_id, user_id)
  end

  @doc """
  Exclui uma sala quando o usuário atual é seu criador.
  """
  def delete(socket, room_id, user_id) do
    OK.for do
      room <- authorize_room_owner(room_id, user_id)
      _deleted_room <- Rooms.delete_room(room)
    after
      transition_after_delete(socket, room_id)
    end
    |> with_original_socket(socket)
  end

  defp find_room(room_id) do
    case Rooms.get_room(room_id) do
      nil -> {:error, :not_found}
      room -> {:ok, room}
    end
  end

  defp authorize_room_owner(room_id, user_id) do
    case Rooms.get_room(room_id) do
      %{creator_id: ^user_id} = room -> {:ok, room}
      _room -> {:error, :not_authorized}
    end
  end

  defp preload_room(room), do: Repo.preload(room, [:creator, :members])

  defp transition_after_create(socket, room) do
    socket
    |> RoomNavigation.refresh()
    |> PubSubManager.subscribe(room)
    |> ChatState.select_room(room)
    |> RoomNavigation.close_dialog()
  end

  defp transition_after_join(socket, room) do
    socket
    |> RoomNavigation.refresh()
    |> PubSubManager.subscribe(room)
    |> ChatState.select_room(room)
    |> RoomNavigation.close_dialog()
    |> assign(:available_rooms, [])
    |> assign(:room_search, "")
  end

  defp transition_after_leave(socket, room_id) do
    socket
    |> PubSubManager.unsubscribe(room_id)
    |> RoomNavigation.refresh()
    |> ChatState.clear_selected_room(room_id)
    |> ChatState.refresh_mentions()
  end

  defp transition_after_delete(socket, room_id) do
    socket
    |> PubSubManager.unsubscribe(room_id)
    |> RoomNavigation.refresh()
    |> ChatState.clear_selected_room(room_id)
    |> ChatState.refresh_mentions()
    |> RoomNavigation.close_dialog()
  end

  defp with_original_socket({:ok, updated_socket}, _socket), do: {:ok, updated_socket}
  defp with_original_socket({:error, reason}, socket), do: {:error, reason, socket}
end
