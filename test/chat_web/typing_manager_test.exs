defmodule ChatWeb.TypingManagerTest do
  use ExUnit.Case, async: false

  import Phoenix.Component, only: [assign: 3]

  alias ChatWeb.Presence
  alias ChatWeb.TypingManager

  setup do
    room_id = "typing-test-#{System.unique_integer([:positive])}"
    topic = "room:#{room_id}"

    socket =
      %Phoenix.LiveView.Socket{}
      |> assign(:current_user, %{id: "user-1", username: "alice"})
      |> assign(:current_room, %{id: room_id})
      |> TypingManager.init()

    on_exit(fn ->
      Presence.untrack(self(), topic, Presence.presence_key("user-1"))
      Presence.untrack(self(), topic, Presence.presence_key("user-2"))
    end)

    %{socket: socket, topic: topic, room_id: room_id}
  end

  describe "init/1" do
    test "sets typing_users to empty list", %{socket: socket} do
      assert socket.assigns.typing_users == []
    end
  end

  describe "update_typing/2" do
    test "sets typing metadata to true via Presence", %{
      socket: socket,
      topic: topic,
      room_id: room_id
    } do
      _socket =
        socket
        |> assign(:current_room, %{id: room_id})
        |> TypingManager.update_typing(true)

      [meta] = Presence.list_online_users(topic)
      assert meta.typing == true
      assert meta.id == "user-1"
    end

    test "updates typing metadata to false", %{socket: socket, topic: topic, room_id: room_id} do
      _socket =
        socket
        |> assign(:current_room, %{id: room_id})
        |> TypingManager.update_typing(true)
        |> TypingManager.update_typing(false)

      [meta] = Presence.list_online_users(topic)
      assert meta.typing == false
    end

    test "returns the socket unchanged", %{socket: socket, room_id: room_id} do
      result =
        socket
        |> assign(:current_room, %{id: room_id})
        |> TypingManager.update_typing(true)

      assert %Phoenix.LiveView.Socket{} = result
    end
  end

  describe "stop_typing/1" do
    test "sets typing metadata to false", %{socket: socket, topic: topic, room_id: room_id} do
      _socket =
        socket
        |> assign(:current_room, %{id: room_id})
        |> TypingManager.update_typing(true)
        |> TypingManager.stop_typing()

      [meta] = Presence.list_online_users(topic)
      assert meta.typing == false
    end
  end

  describe "refresh/1" do
    test "updates typing_users from Presence metadata", %{
      socket: socket,
      topic: topic,
      room_id: room_id
    } do
      bob = %{id: "user-2", username: "bob"}

      bob_pid =
        spawn(fn ->
          {:ok, _} = Presence.track_user(self(), topic, bob)
          {:ok, _} = Presence.update_typing(self(), topic, bob, true)

          receive do
            :done -> :ok
          end
        end)

      on_exit(fn -> send(bob_pid, :done) end)

      Process.sleep(100)

      refreshed =
        socket
        |> assign(:current_room, %{id: room_id})
        |> TypingManager.refresh()

      assert length(refreshed.assigns.typing_users) == 1
      assert hd(refreshed.assigns.typing_users).id == "user-2"
      assert hd(refreshed.assigns.typing_users).username == "bob"
    end

    test "excludes current_user from typing_users", %{socket: socket, room_id: room_id} do
      refreshed =
        socket
        |> assign(:current_room, %{id: room_id})
        |> TypingManager.update_typing(true)
        |> TypingManager.refresh()

      assert refreshed.assigns.typing_users == []
    end
  end
end
