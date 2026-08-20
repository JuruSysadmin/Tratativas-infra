defmodule ChatWeb.ChatPresence do
  @moduledoc """
  Gerenciamento de presença e status de usuários no chat.
  """

  use Phoenix.LiveView

  alias ChatWeb.Presence

  @presence_leave_grace 3_000
  @status_ttl 5_000

  @doc """
  Inicializa o estado de presença no socket.
  """
  def init(socket) do
    socket
    |> assign(:online_users, [])
    |> assign(:status_messages, [])
    |> assign(:status_timers, %{})
    |> assign(:pending_presence_leaves, %{})
  end

  @doc """
  Entra no canal realtime de uma sala.
  """
  def join(socket, room) do
    if connected?(socket) do
      Presence.track_user(self(), room_topic(room.id), socket.assigns.current_user)
    end

    socket
  end

  @doc """
  Sai do canal realtime da sala atual.
  """
  def leave(socket) do
    socket = ChatWeb.TypingManager.stop_typing(socket)

    Enum.each(socket.assigns[:pending_presence_leaves] || %{}, fn {_user_id, pending} ->
      cancel_timer(pending.timer)
    end)

    Enum.each(socket.assigns[:status_timers] || %{}, fn {_id, timer} ->
      cancel_timer(timer)
    end)

    if connected?(socket) && socket.assigns[:current_room] do
      topic = room_topic(socket.assigns.current_room.id)
      Presence.untrack(self(), topic, Presence.presence_key(socket.assigns.current_user.id))
    end

    socket
    |> assign(:status_messages, [])
    |> assign(:status_timers, %{})
  end

  @doc """
  Recarrega a lista de usuários online.
  """
  def refresh_online_users(%{assigns: %{current_room: nil}} = socket), do: socket

  def refresh_online_users(socket) do
    current_user_id = socket.assigns.current_user.id

    online_users =
      socket.assigns.current_room.id
      |> room_topic()
      |> Presence.list_online_users()
      |> Enum.reject(&(&1.id == current_user_id))

    assign(socket, :online_users, online_users)
  end

  @doc """
  Processa mudanças de presença e atualiza status.
  """
  def reconcile(socket, previous_users, online_users, room_id) do
    previous_by_id = Map.new(previous_users, &{&1.id, &1})
    online_by_id = Map.new(online_users, &{&1.id, &1})

    joined_users =
      online_by_id
      |> Map.drop(Map.keys(previous_by_id))
      |> Map.values()

    left_users =
      previous_by_id
      |> Map.drop(Map.keys(online_by_id))
      |> Map.values()

    {socket, joined_statuses} =
      Enum.reduce(joined_users, {socket, []}, fn user, {socket, statuses} ->
        pending_leaves = socket.assigns[:pending_presence_leaves] || %{}

        case Map.pop(pending_leaves, user.id) do
          {%{timer: timer}, remaining_leaves} ->
            cancel_timer(timer)
            {assign(socket, :pending_presence_leaves, remaining_leaves), statuses}

          {nil, _pending_leaves} ->
            {socket, statuses ++ [%{kind: :joined, username: user.username}]}
        end
      end)

    socket =
      Enum.reduce(left_users, socket, fn user, socket ->
        pending_leaves = socket.assigns[:pending_presence_leaves] || %{}
        cancel_pending_leave(Map.get(pending_leaves, user.id))

        timer_token = make_ref()

        timer =
          Process.send_after(
            self(),
            {:confirm_presence_leave, room_id, user.id, timer_token},
            @presence_leave_grace
          )

        pending = %{user: user, timer: timer, token: timer_token}
        assign(socket, :pending_presence_leaves, Map.put(pending_leaves, user.id, pending))
      end)

    append_status_messages(socket, joined_statuses)
  end

  @doc """
  Confirma a saída de um usuário após o timeout de grace.
  """
  def confirm_leave(socket, room_id, user_id, timer_token) do
    pending_leaves = socket.assigns[:pending_presence_leaves] || %{}

    case Map.get(pending_leaves, user_id) do
      %{user: user, timer: timer, token: ^timer_token} ->
        cancel_timer(timer)
        socket = assign(socket, :pending_presence_leaves, Map.delete(pending_leaves, user_id))

        if selected_room?(socket, room_id) &&
             Enum.all?(Presence.list_online_users(room_topic(room_id)), &(&1.id != user_id)) do
          append_status_messages(socket, [%{kind: :left, username: user.username}])
        else
          socket
        end

      _pending ->
        socket
    end
  end

  defp append_status_messages(socket, statuses) do
    current_statuses = socket.assigns[:status_messages] || []
    current_timers = socket.assigns[:status_timers] || %{}

    {new_statuses, new_timers} =
      Enum.reduce(statuses, {[], current_timers}, fn status, {acc_statuses, acc_timers} ->
        id = System.unique_integer([:positive, :monotonic])
        status_with_id = Map.put(status, :id, id)

        timer =
          Process.send_after(self(), {:dismiss_status, id}, @status_ttl)

        {[status_with_id | acc_statuses], Map.put(acc_timers, id, timer)}
      end)

    socket
    |> assign(:status_messages, current_statuses ++ Enum.reverse(new_statuses))
    |> assign(:status_timers, new_timers)
  end

  def dismiss_status(socket, id) do
    timers = socket.assigns[:status_timers] || %{}

    case Map.pop(timers, id) do
      {nil, _remaining_timers} ->
        socket

      {timer, remaining_timers} ->
        cancel_timer(timer)

        socket
        |> assign(:status_messages, Enum.reject(socket.assigns.status_messages, &(&1.id == id)))
        |> assign(:status_timers, remaining_timers)
    end
  end

  defp cancel_pending_leave(nil), do: :ok
  defp cancel_pending_leave(%{timer: timer}), do: cancel_timer(timer)

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer)

  defp selected_room?(socket, room_id) do
    socket.assigns.current_room && socket.assigns.current_room.id == room_id
  end

  defp room_topic(room_id), do: "room:#{room_id}"
end
