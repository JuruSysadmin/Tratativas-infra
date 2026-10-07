defmodule ChatWeb.GlobalPresenceChannelTest do
  use ExUnit.Case, async: false

  import Phoenix.ChannelTest

  alias ChatWeb.GlobalPresenceChannel
  alias ChatWeb.Presence
  alias ChatWeb.UserSocket

  @endpoint ChatWeb.Endpoint
  @topic "presence:global"

  setup do
    Phoenix.PubSub.subscribe(Chat.PubSub, @topic)

    on_exit(fn ->
      # Leave sockets via process exit; Presence cleans tracked pids.
      :ok
    end)

    :ok
  end

  test "authenticated user can join and receives presence_state" do
    user = %{id: "global-presence-join", username: "alice"}

    assert {:ok, %{}, socket} =
             UserSocket
             |> socket("global-presence-join", %{current_user: user})
             |> subscribe_and_join(GlobalPresenceChannel, @topic)

    assert_push "presence_state", state
    assert Map.has_key?(state, Presence.presence_key(user.id))

    online = Presence.list_online_users(@topic)
    assert Enum.any?(online, &(&1.id == user.id and &1.username == user.username))
    assert Enum.all?(online, &(not Map.has_key?(&1, :typing)))

    Process.unlink(socket.channel_pid)
    :ok = close(socket)
  end

  test "join without current_user is forbidden" do
    assert {:error, %{reason: "forbidden"}} =
             UserSocket
             |> socket("global-presence-anon", %{})
             |> subscribe_and_join(GlobalPresenceChannel, @topic)
  end

  test "two authenticated users appear in the global online list" do
    alice = %{id: "global-presence-alice", username: "alice"}
    bob = %{id: "global-presence-bob", username: "bob"}

    assert {:ok, %{}, alice_socket} =
             UserSocket
             |> socket("global-presence-alice", %{current_user: alice})
             |> subscribe_and_join(GlobalPresenceChannel, @topic)

    assert_push "presence_state", _alice_state

    assert {:ok, %{}, bob_socket} =
             UserSocket
             |> socket("global-presence-bob", %{current_user: bob})
             |> subscribe_and_join(GlobalPresenceChannel, @topic)

    assert_push "presence_state", bob_state
    assert Map.has_key?(bob_state, Presence.presence_key(alice.id))
    assert Map.has_key?(bob_state, Presence.presence_key(bob.id))

    online_ids =
      @topic
      |> Presence.list_online_users()
      |> Enum.map(& &1.id)
      |> MapSet.new()

    assert MapSet.subset?(MapSet.new([alice.id, bob.id]), online_ids)

    Process.unlink(alice_socket.channel_pid)
    Process.unlink(bob_socket.channel_pid)
    :ok = close(alice_socket)
    :ok = close(bob_socket)
  end

  test "same user with two sockets shares one presence key with multiple metas" do
    user = %{id: "global-presence-tabs", username: "tabs"}

    assert {:ok, %{}, first} =
             UserSocket
             |> socket("global-presence-tab-1", %{current_user: user})
             |> subscribe_and_join(GlobalPresenceChannel, @topic)

    assert_push "presence_state", _

    assert {:ok, %{}, second} =
             UserSocket
             |> socket("global-presence-tab-2", %{current_user: user})
             |> subscribe_and_join(GlobalPresenceChannel, @topic)

    assert_push "presence_state", state

    key = Presence.presence_key(user.id)
    assert %{metas: metas} = state[key]
    assert length(metas) >= 2

    Process.unlink(first.channel_pid)
    Process.unlink(second.channel_pid)
    :ok = close(first)
    :ok = close(second)
  end
end
