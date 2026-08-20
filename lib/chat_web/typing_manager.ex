defmodule ChatWeb.TypingManager do
  @moduledoc """
  Manages typing indicator state using Phoenix.Presence metadata.

  All functions take a socket and return an updated socket. Typing state is
  stored in Presence (not in timers or local broadcasts), so it works across
  cluster nodes via CRDTs.
  """

  import Phoenix.Component, only: [assign: 3]

  alias ChatWeb.Presence

  @doc """
  Initializes typing-related assigns on a socket.
  """
  def init(socket) do
    assign(socket, :typing_users, [])
  end

  @doc """
  Called when the current user's input changes.

  Updates Presence metadata with `typing: true` or `typing: false`.
  """
  def update_typing(socket, typing?) do
    current_room = socket.assigns.current_room
    user = socket.assigns.current_user

    if current_room do
      Presence.update_typing(
        self(),
        room_topic(current_room.id),
        user,
        typing?
      )
    end

    socket
  end

  @doc """
  Stops typing for the current user.
  """
  def stop_typing(socket) do
    update_typing(socket, false)
  end

  @doc """
  Refreshes the list of remote typing users from Presence metadata.
  """
  def refresh(socket) do
    current_room = socket.assigns.current_room

    if current_room do
      typing_users =
        current_room.id
        |> room_topic()
        |> Presence.list_typing_users(socket.assigns.current_user.id)

      assign(socket, :typing_users, typing_users)
    else
      socket
    end
  end

  defp room_topic(room_id), do: "room:#{room_id}"
end
