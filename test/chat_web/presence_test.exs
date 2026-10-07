defmodule ChatWeb.PresenceTest do
  use ExUnit.Case, async: false

  alias ChatWeb.Presence

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
  test "track_online/3 tracks without typing metadata", %{topic: topic} do
    user = %{id: "user-1", username: "alice"}

    {:ok, _} = Presence.track_online(self(), topic, user)

    assert [meta] = Presence.list_online_users(topic)
    assert meta.id == "user-1"
    assert meta.username == "alice"
    assert meta.joined_at
    refute Map.has_key?(meta, :typing)
  end
end
