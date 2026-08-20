defmodule Chat.Broadcaster do
  @moduledoc "PubSub broadcaster for persisted room events."

  require Logger

  def broadcast_message_created(room_id, message, opts \\ []) do
    broadcast(
      room_id,
      {:message_created, message},
      "message_created",
      [room_id: room_id, message_id: message.id],
      opts
    )
  end

  def broadcast_message_updated(room_id, message, opts \\ []) do
    broadcast(
      room_id,
      {:message_updated, message},
      "message_updated",
      [room_id: room_id, message_id: message.id],
      opts
    )
  end

  def broadcast_message_deleted(room_id, message_id, opts \\ []) do
    broadcast(
      room_id,
      {:message_deleted, room_id, message_id},
      "message_deleted",
      [room_id: room_id, message_id: message_id],
      opts
    )
  end

  def broadcast_read_receipts_updated(room_id, user_id, message_ids, opts \\ []) do
    broadcast(
      room_id,
      {:read_receipts_updated, room_id, user_id, message_ids},
      "read_receipts_updated",
      [room_id: room_id, user_id: user_id, message_ids: message_ids],
      opts
    )
  end

  def broadcast_delivery_receipts_updated(room_id, user_id, message_ids, opts \\ []) do
    broadcast(
      room_id,
      {:delivery_receipts_updated, room_id, user_id, message_ids},
      "delivery_receipts_updated",
      [room_id: room_id, user_id: user_id, message_ids: message_ids],
      opts
    )
  end

  def broadcast_mentions_created(message, mentions, opts \\ []) do
    pubsub = Keyword.get(opts, :pubsub, Phoenix.PubSub)

    mentions
    |> Enum.map(& &1.mentioned_user_id)
    |> Enum.uniq()
    |> Enum.reject(&(&1 == message.user_id))
    |> Enum.each(fn mentioned_user_id ->
      event =
        {:mention_created,
         %{
           message_id: message.id,
           room_id: message.room_id,
           sender_id: message.user_id
         }}

      case pubsub.broadcast(Chat.PubSub, user_topic(mentioned_user_id), event) do
        :ok ->
          :ok

        {:error, reason} ->
          log_failure("mention_created", [user_id: mentioned_user_id], inspect(reason))
      end
    end)
  rescue
    exception ->
      log_failure("mention_created", [message_id: message.id], Exception.message(exception))
  catch
    :exit, reason ->
      log_failure("mention_created", [message_id: message.id], inspect(reason))
  end

  def broadcast_mentions_deleted(message, mentioned_user_ids, opts \\ []) do
    pubsub = Keyword.get(opts, :pubsub, Phoenix.PubSub)

    mentioned_user_ids
    |> Enum.uniq()
    |> Enum.reject(&(&1 == message.user_id))
    |> Enum.each(fn mentioned_user_id ->
      event = {:mention_deleted, %{message_id: message.id, room_id: message.room_id}}

      case pubsub.broadcast(Chat.PubSub, user_topic(mentioned_user_id), event) do
        :ok ->
          :ok

        {:error, reason} ->
          log_failure("mention_deleted", [user_id: mentioned_user_id], inspect(reason))
      end
    end)
  rescue
    exception ->
      log_failure("mention_deleted", [message_id: message.id], Exception.message(exception))
  catch
    :exit, reason ->
      log_failure("mention_deleted", [message_id: message.id], inspect(reason))
  end

  def broadcast_room_deleted(room_id, member_ids, opts \\ []) do
    pubsub = Keyword.get(opts, :pubsub, Phoenix.PubSub)

    member_ids
    |> Enum.uniq()
    |> Enum.each(fn member_id ->
      event = {:room_deleted, %{room_id: room_id}}

      case pubsub.broadcast(Chat.PubSub, user_topic(member_id), event) do
        :ok ->
          :ok

        {:error, reason} ->
          log_failure("room_deleted", [room_id: room_id, user_id: member_id], inspect(reason))
      end
    end)
  rescue
    exception ->
      log_failure("room_deleted", [room_id: room_id], Exception.message(exception))
  catch
    :exit, reason ->
      log_failure("room_deleted", [room_id: room_id], inspect(reason))
  end

  def broadcast_mention_state_changed(user_id, room_id, opts \\ []) do
    pubsub = Keyword.get(opts, :pubsub, Phoenix.PubSub)
    event = {:mention_state_changed, %{room_id: room_id}}

    case pubsub.broadcast(Chat.PubSub, user_topic(user_id), event) do
      :ok ->
        :ok

      {:error, reason} ->
        log_failure("mention_state_changed", [user_id: user_id], inspect(reason))
    end
  rescue
    exception ->
      log_failure("mention_state_changed", [user_id: user_id], Exception.message(exception))
  catch
    :exit, reason ->
      log_failure("mention_state_changed", [user_id: user_id], inspect(reason))
  end

  def broadcast_membership_left(user_id, room_id, opts \\ []) do
    pubsub = Keyword.get(opts, :pubsub, Phoenix.PubSub)
    event = {:membership_left, %{room_id: room_id}}

    case pubsub.broadcast(Chat.PubSub, user_topic(user_id), event) do
      :ok -> :ok
      {:error, reason} -> log_failure("membership_left", [user_id: user_id], inspect(reason))
    end
  rescue
    exception ->
      log_failure("membership_left", [user_id: user_id], Exception.message(exception))
  catch
    :exit, reason ->
      log_failure("membership_left", [user_id: user_id], inspect(reason))
  end

  defp broadcast(room_id, event, event_name, metadata, opts) do
    pubsub = Keyword.get(opts, :pubsub, Phoenix.PubSub)

    result =
      case Keyword.get(opts, :from) do
        nil -> pubsub.broadcast(Chat.PubSub, topic(room_id), event)
        from -> pubsub.broadcast_from(Chat.PubSub, from, topic(room_id), event)
      end

    case result do
      :ok -> :ok
      {:error, reason} -> log_failure(event_name, metadata, inspect(reason))
    end
  rescue
    exception ->
      log_failure(event_name, metadata, Exception.message(exception))
  catch
    :exit, reason ->
      log_failure(event_name, metadata, inspect(reason))
  end

  defp log_failure(event_name, metadata, error) do
    Logger.error("#{event_name} broadcast failed", Keyword.put(metadata, :error, error))
    :ok
  end

  defp topic(room_id), do: "room:#{room_id}"
  defp user_topic(user_id), do: "user:#{user_id}"
end
