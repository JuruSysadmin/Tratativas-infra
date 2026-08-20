defmodule Chat.BroadcastExitStub do
  @moduledoc false

  def broadcast_message_created(room_id, message) do
    send(self(), {:broadcast_exit_attempted, room_id, message.id})
    exit(:broadcast_unavailable)
  end

  def broadcast(_server, _topic, event) do
    send(self(), {:pubsub_broadcast_exit_attempted, event})
    exit(:broadcast_unavailable)
  end
end
