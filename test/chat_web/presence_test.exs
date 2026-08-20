defmodule ChatWeb.PresenceTest do
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias ChatWeb.ChatPresence
  alias ChatWeb.Presence
  alias ChatWeb.PresencePanelComponent

  setup do
    # The application already starts Chat.PubSub and ChatWeb.Presence in test.
    # Use a unique topic per test to avoid cross-test interference.
    topic = "room:presence-test-#{System.unique_integer([:positive])}"
    Phoenix.PubSub.subscribe(Chat.PubSub, topic)

    on_exit(fn ->
      Presence.untrack(self(), topic, Presence.presence_key("user-1"))
      Presence.untrack(self(), topic, Presence.presence_key("user-2"))
      Presence.untrack(self(), topic, Presence.presence_key("user-3"))
    end)

    %{topic: topic}
  end

  test "presence_key/1 returns string keys" do
    assert Presence.presence_key("user-1") == "user-1"
    assert Presence.presence_key(123) == "123"
  end

  test "track_user/3 tracks a user with default typing metadata", %{topic: topic} do
    user = %{id: "user-1", username: "alice"}

    {:ok, _} = Presence.track_user(self(), topic, user)

    assert [meta] = Presence.list_online_users(topic)
    assert meta.id == "user-1"
    assert meta.username == "alice"
    assert meta.typing == false
    assert meta.joined_at
  end

  test "update_typing/4 preserves joined_at and sets typing: true + typing_at", %{topic: topic} do
    user = %{id: "user-1", username: "alice"}

    {:ok, _} = Presence.track_user(self(), topic, user)
    [before_meta] = Presence.list_online_users(topic)

    assert {:ok, _} = Presence.update_typing(self(), topic, user, true)

    [after_meta] = Presence.list_online_users(topic)
    assert after_meta.id == "user-1"
    assert after_meta.username == "alice"
    assert after_meta.typing == true
    assert is_integer(after_meta.typing_at)
    assert after_meta.joined_at == before_meta.joined_at
  end

  test "update_typing/4 sets typing: false", %{topic: topic} do
    user = %{id: "user-1", username: "alice"}

    {:ok, _} = Presence.track_user(self(), topic, user)
    assert {:ok, _} = Presence.update_typing(self(), topic, user, true)
    assert {:ok, _} = Presence.update_typing(self(), topic, user, false)

    [meta] = Presence.list_online_users(topic)
    assert meta.typing == false
  end

  test "update_typing/4 works without previous track", %{topic: topic} do
    user = %{id: "user-1", username: "alice"}

    assert {:ok, _} = Presence.update_typing(self(), topic, user, true)

    assert [meta] = Presence.list_online_users(topic)
    assert meta.id == "user-1"
    assert meta.username == "alice"
    assert meta.typing == true
    assert is_integer(meta.typing_at)
  end

  test "list_typing_users/2 returns only users typing, excluding current_user, sorted by username",
       %{topic: topic} do
    alice = %{id: "user-1", username: "alice"}
    bob = %{id: "user-2", username: "bob"}
    carol = %{id: "user-3", username: "carol"}

    {:ok, _} = Presence.track_user(self(), topic, alice)
    {:ok, _} = Presence.update_typing(self(), topic, alice, true)

    bob_pid =
      spawn(fn ->
        {:ok, _} = Presence.track_user(self(), topic, bob)
        {:ok, _} = Presence.update_typing(self(), topic, bob, true)

        receive do
          :done -> :ok
        end
      end)

    carol_pid =
      spawn(fn ->
        {:ok, _} = Presence.track_user(self(), topic, carol)

        receive do
          :done -> :ok
        end
      end)

    on_exit(fn ->
      send(bob_pid, :done)
      send(carol_pid, :done)
    end)

    Process.sleep(100)

    typing = Presence.list_typing_users(topic, alice.id)
    assert length(typing) == 1
    assert hd(typing).id == bob.id
  end

  test "dismiss_status ignores unknown status ids" do
    socket =
      %Phoenix.LiveView.Socket{}
      |> Phoenix.Component.assign(:status_messages, [%{id: 1, kind: :joined}])
      |> Phoenix.Component.assign(:status_timers, %{})

    assert ChatPresence.dismiss_status(socket, 2) == socket
  end

  test "ignores a stale leave confirmation from a canceled timer" do
    current_user = %{id: "user-1", username: "Alice"}
    departing_user = %{id: "user-2", username: "Bob"}
    room_id = "room-1"
    stale_timer_token = make_ref()

    socket =
      presence_socket(current_user, room_id)
      |> ChatPresence.init()
      |> Phoenix.Component.assign(
        :pending_presence_leaves,
        %{departing_user.id => %{user: departing_user, timer: nil, token: stale_timer_token}}
      )

    send(self(), {:confirm_presence_leave, room_id, departing_user.id, stale_timer_token})

    socket = ChatPresence.reconcile(socket, [departing_user], [], room_id)
    active_pending = socket.assigns.pending_presence_leaves[departing_user.id]
    assert active_pending.token != stale_timer_token

    socket =
      ChatPresence.confirm_leave(
        socket,
        room_id,
        departing_user.id,
        stale_timer_token
      )

    assert socket.assigns.pending_presence_leaves[departing_user.id] == active_pending
    assert socket.assigns.status_messages == []
  end

  test "presence panel count includes the current user and every other online user" do
    current_user = %{id: "user-1", username: "Alice"}
    bob = %{id: "user-2", username: "Bob"}
    carol = %{id: "user-3", username: "Carol"}

    assert_presence_count(current_user, [bob], 2)
    assert_presence_count(current_user, [bob, carol], 3)
  end

  test "presence panel does not duplicate current user when online_users already includes it" do
    current_user = %{id: "user-1", username: "Alice"}
    bob = %{id: "user-2", username: "Bob"}

    html =
      render_component(&PresencePanelComponent.presence_panel/1,
        current_user: current_user,
        current_room: %{id: "room-1"},
        online_users: [current_user, bob, bob]
      )

    assert html =~ "2 participantes online"
    assert length(Regex.scan(~r/<li(?:\s|>)/, html)) == 2
    assert length(Regex.scan(~r/Alice/, html)) == 1
    assert length(Regex.scan(~r/Bob/, html)) == 1
  end

  test "presence panel renders Carbon status indicators with accessible online text" do
    current_user = %{id: "user-1", username: "Alice"}
    bob = %{id: "user-2", username: "Bob"}

    html =
      render_component(&PresencePanelComponent.presence_panel/1,
        current_user: current_user,
        current_room: %{id: "room-1"},
        online_users: [bob]
      )

    assert html =~ ~s(class="cds-status-indicator cds-status-indicator--success")
    assert html =~ ~s(aria-label="2 participantes online")
    assert html =~ "online nesta sala"
    assert html =~ "2 participantes online"
  end

  test "presence panel is hidden when no room is selected" do
    html =
      render_component(&PresencePanelComponent.presence_panel/1,
        current_user: %{id: "user-1", username: "Alice"},
        current_room: nil,
        online_users: []
      )

    refute html =~ ~s(id="presence-panel")
    refute html =~ "Na sala"
  end

  test "users tracked in the same room produce the matching online count", %{topic: topic} do
    current_user = %{id: "user-1", username: "Alice"}
    bob = %{id: "user-2", username: "Bob"}
    carol = %{id: "user-3", username: "Carol"}
    room_id = String.replace_prefix(topic, "room:", "")

    {:ok, _} = Presence.track_user(self(), topic, current_user)
    bob_pid = track_user_in_process(topic, bob)

    socket = presence_socket(current_user, room_id) |> ChatPresence.refresh_online_users()
    assert_presence_count(current_user, socket.assigns.online_users, 2)

    carol_pid = track_user_in_process(topic, carol)
    socket = ChatPresence.refresh_online_users(socket)
    assert_presence_count(current_user, socket.assigns.online_users, 3)

    on_exit(fn ->
      send(bob_pid, :done)
      send(carol_pid, :done)
    end)
  end

  defp assert_presence_count(current_user, online_users, expected_count) do
    html =
      render_component(&PresencePanelComponent.presence_panel/1,
        current_user: current_user,
        current_room: %{id: "room-1"},
        online_users: online_users
      )

    assert html =~ "#{expected_count} participantes online"
    refute html =~ "Na sala"
    assert length(Regex.scan(~r/<li(?:\s|>)/, html)) == expected_count
    assert html =~ "#{current_user.username} (você)"

    Enum.each(online_users, fn user ->
      assert html =~ user.username
    end)
  end

  defp track_user_in_process(topic, user) do
    parent = self()

    pid =
      spawn(fn ->
        {:ok, _} = Presence.track_user(self(), topic, user)
        send(parent, {:presence_tracked, self()})

        receive do
          :done -> :ok
        end
      end)

    assert_receive {:presence_tracked, ^pid}
    pid
  end

  defp presence_socket(current_user, room_id) do
    %Phoenix.LiveView.Socket{}
    |> Phoenix.Component.assign(%{
      current_user: current_user,
      current_room: %{id: room_id}
    })
  end
end
