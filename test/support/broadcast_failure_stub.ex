defmodule Chat.BroadcastFailureStub do
  @moduledoc false

  def broadcast_message_created(room_id, message) do
    send(self(), {:broadcast_attempted, room_id, message.id})
    raise "broadcast unavailable"
  end

  def broadcast_message_updated(room_id, message) do
    send(self(), {:edit_broadcast_attempted, room_id, message.id})
    raise "broadcast unavailable"
  end

  def broadcast_mentions_created(message, mentions) do
    send(self(), {:mention_broadcast_attempted, message.id, length(mentions)})
    raise "mention broadcast unavailable"
  end

  def broadcast(_server, _topic, event) do
    send(self(), {:pubsub_broadcast_attempted, event})
    raise "broadcast unavailable"
  end
end
