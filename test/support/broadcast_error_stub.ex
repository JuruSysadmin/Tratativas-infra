defmodule Chat.BroadcastErrorStub do
  @moduledoc false

  def broadcast(_server, _topic, event) do
    send(self(), {:pubsub_broadcast_error, event})
    {:error, :no_such_group}
  end
end
