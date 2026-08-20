defmodule ChatWeb.Presence do
  @moduledoc "Tracks and queries users connected to chat room topics."

  use Phoenix.Presence,
    otp_app: :chat,
    pubsub_server: Chat.PubSub

  @doc """
  Returns a string presence key for a user id.
  """
  def presence_key(user_id), do: to_string(user_id)

  @doc """
  Tracks a user on a topic with standardized metadata.
  """
  def track_user(pid, topic, user) when is_pid(pid) do
    track(pid, topic, presence_key(user.id), initial_meta(user))
  end

  def track_user(%Phoenix.Socket{} = socket, user) do
    track(socket, presence_key(user.id), initial_meta(user))
  end

  @doc """
  Updates the typing flag for a user on a topic, preserving existing metadata.
  """
  def update_typing(%Phoenix.Socket{} = socket, user, typing?) do
    key = presence_key(user.id)
    ensure_tracked(socket, key, user)
    new_meta = build_meta(socket, key, user, typing?)
    update(socket, key, new_meta)
  end

  def update_typing(pid, topic, user, typing?) when is_pid(pid) do
    key = presence_key(user.id)
    ensure_tracked(pid, topic, key, user)
    new_meta = build_meta(topic, key, user, typing?)
    update(pid, topic, key, new_meta)
  end

  @doc """
  Returns users currently typing on a topic, excluding the given user id.
  """
  def list_typing_users(topic, current_user_id) do
    topic
    |> list_online_users()
    |> Enum.reject(&(&1.id == current_user_id))
    |> Enum.filter(&(Map.get(&1, :typing, false) == true))
    |> Enum.sort_by(& &1.username)
  end

  @doc """
  Returns a map of online users for a given topic.
  """
  def list_online_users(topic) do
    list(topic)
    |> Enum.map(fn {_key, %{metas: [meta | _]}} ->
      meta
    end)
  end

  @doc """
  Returns the count of online users for a given topic.
  """
  def count_online(topic) do
    list(topic) |> map_size()
  end

  defp initial_meta(user) do
    %{
      id: user.id,
      username: user.username,
      joined_at: DateTime.utc_now(),
      typing: false
    }
  end

  defp build_meta(%Phoenix.Socket{} = socket, key, user, typing?) do
    topic = "room:#{socket.assigns.room_id}"
    build_meta(topic, key, user, typing?)
  end

  defp build_meta(topic, key, user, typing?) do
    current_meta(topic, key)
    |> Map.put(:id, user.id)
    |> Map.put(:username, user.username)
    |> Map.put(:typing, typing?)
    |> then(fn meta ->
      if typing?, do: Map.put(meta, :typing_at, System.monotonic_time(:millisecond)), else: meta
    end)
  end

  defp ensure_tracked(%Phoenix.Socket{} = socket, key, user) do
    topic = "room:#{socket.assigns.room_id}"
    ensure_tracked(topic, key, user, socket)
  end

  defp ensure_tracked(pid, topic, key, user) when is_pid(pid) do
    ensure_tracked(topic, key, user, pid)
  end

  defp ensure_tracked(topic, key, user, tracker) do
    unless tracked?(topic, key) do
      track(tracker, topic, key, initial_meta(user))
    end
  end

  defp tracked?(topic, key) do
    case list(topic) do
      %{^key => _} -> true
      _ -> false
    end
  end

  defp current_meta(topic, key) do
    case list(topic) do
      %{^key => %{metas: [meta | _]}} -> meta
      _ -> %{}
    end
  end
end
