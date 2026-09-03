defmodule Chat.BroadcastCommitVisibilityStub do
  @moduledoc false

  alias Chat.Messages.Message
  alias Chat.Repo
  alias Ecto.Adapters.SQL.Sandbox

  def broadcast_message_created(room_id, message) do
    persisted? =
      Sandbox.unboxed_run(Repo, fn ->
        Repo.get(Message, message.id) != nil
      end)

    send(self(), {:broadcast_saw_committed_message, room_id, message.id, persisted?})
    :ok
  end

  def broadcast_mentions_created(_message, _mentions), do: :ok
end
