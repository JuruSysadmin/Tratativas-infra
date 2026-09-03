defmodule Chat.BroadcasterTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Chat.Broadcaster

  test "broadcasts room events directly through PubSub" do
    room_id = Ecto.UUID.generate()
    message = %{id: Ecto.UUID.generate(), room_id: room_id}

    Phoenix.PubSub.subscribe(Chat.PubSub, "room:#{room_id}")

    assert :ok = Broadcaster.broadcast_message_created(room_id, message)
    assert_receive {:message_created, ^message}

    assert :ok = Broadcaster.broadcast_message_deleted(room_id, message.id)
    assert_receive {:message_deleted, ^room_id, message_id}
    assert message_id == message.id

    assert :ok = Broadcaster.broadcast_message_updated(room_id, message)
    assert_receive {:message_updated, ^message}
  end

  test "broadcasts read receipts as one grouped event" do
    room_id = Ecto.UUID.generate()
    user_id = Ecto.UUID.generate()
    message_ids = [Ecto.UUID.generate(), Ecto.UUID.generate()]

    Phoenix.PubSub.subscribe(Chat.PubSub, "room:#{room_id}")

    assert :ok =
             Broadcaster.broadcast_read_receipts_updated(room_id, user_id, message_ids)

    assert_receive {:read_receipts_updated, ^room_id, ^user_id, ^message_ids}
    refute_receive {:read_receipt_updated, _, _, _}
  end

  test "notifies the assigned agent but not the sender" do
    room_id = Ecto.UUID.generate()
    message_id = Ecto.UUID.generate()
    assigned_agent_id = Ecto.UUID.generate()
    message = %{id: message_id, room_id: room_id}

    Phoenix.PubSub.subscribe(Chat.PubSub, "user:#{assigned_agent_id}")

    assert :ok =
             Broadcaster.broadcast_assigned_room_message(message, assigned_agent_id,
               sender_id: Ecto.UUID.generate()
             )

    assert_receive {:assigned_room_message_created, %{room_id: ^room_id, message_id: ^message_id}}

    assert :ok =
             Broadcaster.broadcast_assigned_room_message(message, assigned_agent_id,
               sender_id: assigned_agent_id
             )

    refute_receive {:assigned_room_message_created, _}
  end

  test "deletion broadcast failure is logged without escaping" do
    room_id = Ecto.UUID.generate()
    message_id = Ecto.UUID.generate()

    log =
      capture_log(fn ->
        assert :ok =
                 Broadcaster.broadcast_message_deleted(room_id, message_id,
                   pubsub: Chat.BroadcastFailureStub
                 )

        assert_receive {:pubsub_broadcast_attempted, {:message_deleted, ^room_id, ^message_id}}
      end)

    assert log =~ "message_deleted broadcast failed"
  end

  test "read receipt broadcast exit is logged without escaping" do
    room_id = Ecto.UUID.generate()
    user_id = Ecto.UUID.generate()
    message_ids = [Ecto.UUID.generate()]

    log =
      capture_log(fn ->
        assert :ok =
                 Broadcaster.broadcast_read_receipts_updated(room_id, user_id, message_ids,
                   pubsub: Chat.BroadcastExitStub
                 )

        assert_receive {:pubsub_broadcast_exit_attempted,
                        {:read_receipts_updated, ^room_id, ^user_id, ^message_ids}}
      end)

    assert log =~ "read_receipts_updated broadcast failed"
  end

  test "normal PubSub error is logged without escaping" do
    room_id = Ecto.UUID.generate()
    message = %{id: Ecto.UUID.generate(), room_id: room_id}

    log =
      capture_log(fn ->
        assert :ok =
                 Broadcaster.broadcast_message_created(room_id, message,
                   pubsub: Chat.BroadcastErrorStub
                 )

        assert_receive {:pubsub_broadcast_error, {:message_created, ^message}}
      end)

    assert log =~ "message_created broadcast failed"
    assert log =~ "no_such_group"
  end

  test "broadcasts treatment lifecycle events to the queue topic" do
    created = %{treatment_id: Ecto.UUID.generate(), status: "open"}
    updated = %{treatment_id: created.treatment_id, status: "in_progress"}

    Phoenix.PubSub.subscribe(Chat.PubSub, "treatments:queue")

    assert :ok = Broadcaster.broadcast_treatment_created(created)

    assert_receive %Phoenix.Socket.Broadcast{
      topic: "treatments:queue",
      event: "treatment:created",
      payload: ^created
    }

    assert :ok = Broadcaster.broadcast_treatment_updated(updated)

    assert_receive %Phoenix.Socket.Broadcast{
      topic: "treatments:queue",
      event: "treatment:updated",
      payload: ^updated
    }
  end

  test "treatment update broadcast error is logged without escaping" do
    log =
      capture_log(fn ->
        assert :ok =
                 Broadcaster.broadcast_treatment_updated(%{treatment_id: Ecto.UUID.generate()},
                   pubsub: Chat.BroadcastErrorStub
                 )
      end)

    assert log =~ "treatment_updated broadcast failed"
    assert log =~ "no_such_group"
  end
end
