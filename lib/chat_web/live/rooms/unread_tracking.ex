defmodule ChatWeb.UnreadTracking do
  @moduledoc """
  Mantém `:unread_counts` sincronizado com as mensagens persistidas.

  As contagens nunca são incrementadas ou removidas apenas em memória: cada
  atualização consulta o estado autorizado no banco.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Chat.Messages

  @doc """
  Recarrega as contagens das salas atualmente atribuídas ao usuário.
  """
  def reload(socket, rooms) do
    user_id = socket.assigns.current_user.id
    unread_counts = Messages.unread_counts_by_room(user_id, Enum.map(rooms, & &1.id))
    assign(socket, :unread_counts, unread_counts)
  end

  @doc """
  Recarrega a contagem de uma sala após a chegada de uma mensagem.
  """
  def increment(socket, room_id) do
    if Enum.any?(socket.assigns.rooms, &(&1.id == room_id)) do
      refresh(socket, room_id)
    else
      socket
    end
  end

  @doc """
  Recarrega a contagem de uma sala após uma ação de leitura.
  """
  def clear(socket, room_id) do
    refresh(socket, room_id)
  end

  @doc """
  Sincroniza a contagem persistida de uma sala no socket.
  """
  def refresh(socket, room_id) do
    unread_counts = socket.assigns[:unread_counts] || %{}
    user_id = socket.assigns.current_user.id

    case Messages.unread_counts_by_room(user_id, [room_id]) do
      %{^room_id => count} ->
        assign(socket, :unread_counts, Map.put(unread_counts, room_id, count))

      %{} ->
        assign(socket, :unread_counts, Map.delete(unread_counts, room_id))
    end
  end
end
