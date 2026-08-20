defmodule Chat.Messages do
  @moduledoc "Message persistence, pagination, deletion, and room broadcasts."

  import Ecto.Query
  require Logger

  alias Chat.Accounts.User

  alias Chat.Messages.{
    Attachments,
    Mention,
    MentionParser,
    Message,
    MessageRevision,
    ReadReceipt,
    RoomDeliveryPosition,
    RoomReadPosition
  }

  alias Chat.Repo
  alias Chat.Rooms
  alias Chat.Rooms.{Room, RoomMember}
  alias Ecto.Multi

  def list_messages(room_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    before_id = Keyword.get(opts, :before)

    active_messages()
    |> where([m], m.room_id == ^room_id)
    |> maybe_filter_before(room_id, before_id)
    |> order_by([m], desc: m.inserted_at, desc: m.id)
    |> limit(^limit)
    |> preload([:user, :mentions, :attachments])
    |> Repo.all()
    |> Enum.reverse()
  end

  @doc "Lists active room messages only while the requester is a current member."
  def list_messages_for_member(user_id, room_id, opts \\ []) do
    with {:ok, user_id} <- Ecto.UUID.cast(user_id),
         {:ok, room_id} <- Ecto.UUID.cast(room_id) do
      limit = Keyword.get(opts, :limit, 50)
      before_id = Keyword.get(opts, :before)
      through_id = Keyword.get(opts, :through)

      active_messages()
      |> join(:inner, [message], membership in RoomMember,
        on: membership.room_id == message.room_id and membership.user_id == ^user_id
      )
      |> where([message, _membership], message.room_id == ^room_id)
      |> maybe_filter_before(room_id, before_id)
      |> maybe_filter_through(user_id, room_id, through_id)
      |> order_by([message, _membership], desc: message.inserted_at, desc: message.id)
      |> limit(^limit)
      |> preload([message, _membership], [:user, :mentions, :attachments])
      |> Repo.all()
      |> Enum.reverse()
    else
      :error -> []
    end
  end

  defp maybe_filter_before(query, _room_id, nil), do: query

  defp maybe_filter_before(query, room_id, before_id) do
    case Repo.get_by(Message, id: before_id, room_id: room_id) do
      nil ->
        where(query, [m], false)

      cursor ->
        where(
          query,
          [m],
          m.inserted_at < ^cursor.inserted_at or
            (m.inserted_at == ^cursor.inserted_at and m.id < ^cursor.id)
        )
    end
  end

  defp maybe_filter_through(query, _user_id, _room_id, nil), do: query

  defp maybe_filter_through(query, user_id, room_id, message_id) do
    with {:ok, message_id} <- Ecto.UUID.cast(message_id),
         %Message{} = cursor <- authorized_message_cursor(user_id, room_id, message_id) do
      where(
        query,
        [message, _membership],
        message.inserted_at < ^cursor.inserted_at or
          (message.inserted_at == ^cursor.inserted_at and message.id <= ^cursor.id)
      )
    else
      _reason -> where(query, [message, _membership], false)
    end
  end

  defp authorized_message_cursor(user_id, room_id, message_id) do
    active_messages()
    |> join(:inner, [message], membership in RoomMember,
      on: membership.room_id == message.room_id and membership.user_id == ^user_id
    )
    |> where(
      [message, _membership],
      message.id == ^message_id and message.room_id == ^room_id
    )
    |> Repo.one()
  end

  def get_message(id) do
    active_messages()
    |> where([m], m.id == ^id)
    |> preload([:user, :mentions, :attachments])
    |> Repo.one()
  end

  def get_message!(id, room_id) do
    active_messages()
    |> where([m], m.id == ^id and m.room_id == ^room_id)
    |> preload([:user, :mentions, :attachments])
    |> Repo.one!()
  end

  def create_message(attrs, user_id, room_id, opts \\ []) do
    broadcaster = Keyword.get(opts, :broadcaster, Chat.Broadcaster)

    with {:ok, client_id} <- cast_client_id(Keyword.get(opts, :client_id)) do
      insert_message(
        attrs,
        user_id,
        room_id,
        client_id,
        Keyword.get(opts, :attachment_ids, []),
        broadcaster
      )
    end
  end

  @doc "Lists persisted mention occurrences addressed to a user in rooms they can access."
  def list_mentions(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    case Ecto.UUID.cast(user_id) do
      {:ok, user_id} ->
        Mention
        |> join(:inner, [mention], message in assoc(mention, :message))
        |> join(:inner, [_mention, message], membership in RoomMember,
          on: membership.room_id == message.room_id and membership.user_id == ^user_id
        )
        |> where(
          [mention, message, _membership],
          mention.mentioned_user_id == ^user_id and is_nil(message.deleted_at)
        )
        |> order_by([mention], desc: mention.inserted_at, asc: mention.start_offset)
        |> limit(^limit)
        |> Repo.all()
        |> Repo.preload(message: [:user, :room])

      :error ->
        []
    end
  end

  @doc "Lists distinct persisted mention notifications for a user's current rooms."
  def list_mention_notifications(user_id, opts \\ []) do
    limit = notification_limit(Keyword.get(opts, :limit, 50))

    case Ecto.UUID.cast(user_id) do
      {:ok, user_id} ->
        rows = mention_notification_rows(user_id, limit)
        messages_by_id = mention_messages_by_id(rows, user_id)
        Enum.flat_map(rows, &build_mention_notification(&1, messages_by_id))

      :error ->
        []
    end
  end

  defp mention_notification_rows(user_id, limit) do
    Mention
    |> join(:inner, [mention], message in assoc(mention, :message))
    |> join(:inner, [_mention, message], membership in RoomMember,
      on: membership.room_id == message.room_id and membership.user_id == ^user_id
    )
    |> where(
      [mention, message, _membership],
      mention.mentioned_user_id == ^user_id and message.user_id != ^user_id and
        is_nil(message.deleted_at)
    )
    |> group_by([mention], mention.message_id)
    |> order_by([mention], desc: max(mention.inserted_at), desc: mention.message_id)
    |> select([mention], {mention.message_id, max(mention.inserted_at)})
    |> limit(^limit)
    |> Repo.all()
  end

  defp mention_messages_by_id(rows, user_id) do
    message_ids = Enum.map(rows, &elem(&1, 0))

    Message
    |> join(:inner, [message], mention in Mention,
      on: mention.message_id == message.id and mention.mentioned_user_id == ^user_id
    )
    |> join(:inner, [message, _mention], membership in RoomMember,
      on: membership.room_id == message.room_id and membership.user_id == ^user_id
    )
    |> where(
      [message, _mention, _membership],
      message.id in ^message_ids and message.user_id != ^user_id and is_nil(message.deleted_at)
    )
    |> distinct(true)
    |> preload([message, _mention, _membership], [:user, :room])
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp build_mention_notification({message_id, inserted_at}, messages_by_id) do
    case Map.get(messages_by_id, message_id) do
      %Message{} = message ->
        [%{message_id: message_id, message: message, inserted_at: inserted_at}]

      nil ->
        []
    end
  end

  @doc "Fetches one mention notification under a current membership lock."
  def get_mention_notification(user_id, message_id) do
    with {:ok, user_id} <- Ecto.UUID.cast(user_id),
         {:ok, message_id} <- Ecto.UUID.cast(message_id) do
      query =
        Mention
        |> join(:inner, [mention], message in assoc(mention, :message))
        |> join(:inner, [_mention, message], membership in RoomMember,
          on: membership.room_id == message.room_id and membership.user_id == ^user_id
        )
        |> where(
          [mention, message, _membership],
          mention.message_id == ^message_id and mention.mentioned_user_id == ^user_id and
            message.user_id != ^user_id and is_nil(message.deleted_at)
        )
        |> order_by([mention], asc: mention.start_offset)
        |> limit(1)
        |> lock("FOR SHARE")

      Repo.transaction(fn -> fetch_mention_notification(query) end)
      |> normalize_mention_notification_result()
    else
      :error -> {:error, :invalid_id}
    end
  end

  defp fetch_mention_notification(query) do
    case Repo.one(query) do
      nil -> Repo.rollback(:not_found)
      mention -> Repo.preload(mention, message: [:user, room: [:creator, :members]])
    end
  end

  defp normalize_mention_notification_result({:ok, mention}), do: {:ok, mention}
  defp normalize_mention_notification_result({:error, :not_found}), do: {:error, :not_found}

  defp notification_limit(limit) when is_integer(limit) and limit > 0 and limit <= 100, do: limit
  defp notification_limit(_limit), do: 50

  @doc "Counts unread messages that mention the user across their current rooms."
  def count_unread_mentions(user_id) do
    case Ecto.UUID.cast(user_id) do
      {:ok, user_id} -> unread_mentions_count(user_id)
      :error -> 0
    end
  end

  defp unread_mentions_count(user_id) do
    Mention
    |> join(:inner, [mention], message in Message, on: message.id == mention.message_id)
    |> join(:inner, [_mention, message], membership in RoomMember,
      on: membership.room_id == message.room_id and membership.user_id == ^user_id
    )
    |> join(:left, [_mention, message, _membership], position in RoomReadPosition,
      on: position.room_id == message.room_id and position.user_id == ^user_id
    )
    |> where(
      [mention, message],
      mention.mentioned_user_id == ^user_id and message.user_id != ^user_id and
        is_nil(message.deleted_at)
    )
    |> where(
      [_mention, message, _membership, position],
      is_nil(position.id) or
        message.inserted_at > position.last_read_message_inserted_at or
        (message.inserted_at == position.last_read_message_inserted_at and
           message.id > position.last_read_message_id)
    )
    |> select([_mention, message], count(message.id, :distinct))
    |> Repo.one()
  end

  @doc "Counts unread mentions by room for a user's current memberships."
  def unread_mention_counts_by_room(_user_id, []), do: %{}

  def unread_mention_counts_by_room(user_id, room_ids) when is_list(room_ids) do
    case Ecto.UUID.cast(user_id) do
      {:ok, user_id} -> unread_mention_counts(user_id, room_ids)
      :error -> %{}
    end
  end

  defp unread_mention_counts(user_id, room_ids) do
    Mention
    |> join(:inner, [mention], message in Message, on: message.id == mention.message_id)
    |> join(:inner, [_mention, message], membership in RoomMember,
      on: membership.room_id == message.room_id and membership.user_id == ^user_id
    )
    |> join(:left, [_mention, message, _membership], position in RoomReadPosition,
      on: position.room_id == message.room_id and position.user_id == ^user_id
    )
    |> where(
      [mention, message],
      mention.mentioned_user_id == ^user_id and message.user_id != ^user_id and
        message.room_id in ^room_ids and is_nil(message.deleted_at)
    )
    |> where(
      [_mention, message, _membership, position],
      is_nil(position.id) or
        message.inserted_at > position.last_read_message_inserted_at or
        (message.inserted_at == position.last_read_message_inserted_at and
           message.id > position.last_read_message_id)
    )
    |> group_by([_mention, message], message.room_id)
    |> select([_mention, message], {message.room_id, count(message.id, :distinct)})
    |> Repo.all()
    |> Map.new()
  end

  defp cast_client_id(nil), do: {:ok, nil}

  defp cast_client_id(client_id) do
    case Ecto.UUID.cast(client_id) do
      {:ok, cast_client_id} -> {:ok, cast_client_id}
      :error -> {:error, :invalid_client_id}
    end
  end

  defp insert_message(attrs, user_id, room_id, client_id, attachment_ids, broadcaster) do
    changeset =
      %Message{}
      |> Message.changeset(attrs, allow_empty_content: attachment_ids != [])
      |> Ecto.Changeset.put_change(:user_id, user_id)
      |> Ecto.Changeset.put_change(:room_id, room_id)
      |> maybe_put_client_id(client_id)

    Multi.new()
    |> Multi.run(:locked_room, fn repo, _changes ->
      lock_room_for_mentions(repo, room_id)
    end)
    |> Multi.run(:authorized_sender, fn repo, _changes ->
      authorize_sender(repo, user_id, room_id)
    end)
    |> Multi.insert(:message, changeset)
    |> Multi.run(:attachments, fn repo, %{message: message} ->
      Attachments.attach_to_message(repo, user_id, room_id, message.id, attachment_ids)
    end)
    |> Multi.run(:mentions, fn repo, %{message: message} ->
      insert_mentions(repo, message)
    end)
    |> Multi.run(:message_with_user, &fetch_inserted_message/2)
    |> Repo.transaction()
    |> handle_insert_result(client_id, user_id, room_id, attrs, broadcaster)
  end

  defp fetch_inserted_message(repo, %{message: message}) do
    case repo.one(
           from m in Message,
             where: m.id == ^message.id,
             preload: [:user, :mentions, :attachments]
         ) do
      nil -> {:error, :message_deleted}
      message_with_user -> {:ok, message_with_user}
    end
  end

  defp handle_insert_result(
         {:ok, %{message_with_user: message, mentions: mentions}},
         _client_id,
         _user_id,
         room_id,
         _attrs,
         broadcaster
       ) do
    broadcast_message_created(broadcaster, room_id, message)
    broadcast_mentions_created(broadcaster, message, mentions)
    {:ok, message}
  end

  defp handle_insert_result(
         {:error, :message_with_user, :message_deleted, _changes},
         _client_id,
         _user_id,
         _room_id,
         _attrs,
         _broadcaster
       ),
       do: {:error, :message_deleted}

  defp handle_insert_result(
         {:error, :authorized_sender, :forbidden, _changes},
         _client_id,
         _user_id,
         _room_id,
         _attrs,
         _broadcaster
       ),
       do: {:error, :forbidden}

  defp handle_insert_result(
         {:error, :locked_room, :forbidden, _changes},
         _client_id,
         _user_id,
         _room_id,
         _attrs,
         _broadcaster
       ),
       do: {:error, :forbidden}

  defp handle_insert_result(
         {:error, :attachments, :invalid_attachments, _changes},
         _client_id,
         _user_id,
         _room_id,
         _attrs,
         _broadcaster
       ),
       do: {:error, :invalid_attachments}

  defp handle_insert_result(
         {:error, _operation, changeset, _changes},
         client_id,
         user_id,
         room_id,
         attrs,
         _broadcaster
       ) do
    recover_existing_client_message(client_id, user_id, room_id, attrs, changeset)
  end

  defp recover_existing_client_message(client_id, user_id, room_id, attrs, changeset) do
    case authorized_existing_client_message(client_id, user_id, room_id, attrs) do
      {:ok, message} -> {:ok, message}
      {:error, :forbidden} -> {:error, :forbidden}
      {:error, :client_id_conflict} -> {:error, :client_id_conflict}
      :not_found -> {:error, changeset}
    end
  end

  defp lock_room_for_mentions(repo, room_id) do
    query = from room in Room, where: room.id == ^room_id, lock: "FOR SHARE"

    case repo.one(query) do
      %Room{} -> {:ok, :locked}
      nil -> {:error, :forbidden}
    end
  rescue
    Ecto.Query.CastError -> {:error, :forbidden}
  end

  defp authorize_sender(repo, user_id, room_id) do
    query =
      from membership in RoomMember,
        where: membership.user_id == ^user_id and membership.room_id == ^room_id,
        lock: "FOR SHARE"

    case repo.one(query) do
      %RoomMember{} -> {:ok, :authorized}
      nil -> {:error, :forbidden}
    end
  rescue
    Ecto.Query.CastError -> {:error, :forbidden}
  end

  defp insert_mentions(repo, message) do
    case mention_rows(repo, message) do
      [] ->
        {:ok, []}

      rows ->
        {_count, _mentions} = repo.insert_all(Mention, rows)

        mentions =
          Mention
          |> where([mention], mention.message_id == ^message.id)
          |> order_by([mention], asc: mention.start_offset)
          |> repo.all()

        {:ok, mentions}
    end
  end

  defp mention_rows(repo, message) do
    occurrences = MentionParser.parse(message.content)
    handles = occurrences |> Enum.map(&MentionParser.normalize(&1.handle)) |> Enum.uniq()
    users_by_handle = mentionable_users_by_handle(repo, message.room_id, handles)
    now = DateTime.utc_now()

    Enum.flat_map(occurrences, fn occurrence ->
      case Map.get(users_by_handle, MentionParser.normalize(occurrence.handle)) do
        %User{} = user ->
          [
            %{
              id: Ecto.UUID.generate(),
              message_id: message.id,
              mentioned_user_id: user.id,
              username_snapshot: occurrence.handle,
              start_offset: occurrence.start_offset,
              length: occurrence.length,
              inserted_at: now
            }
          ]

        nil ->
          []
      end
    end)
  end

  defp reconcile_mentions(repo, message) do
    previous_mentioned_user_ids =
      Mention
      |> where([mention], mention.message_id == ^message.id)
      |> select([mention], mention.mentioned_user_id)
      |> distinct(true)
      |> repo.all()

    rows = mention_rows(repo, message)
    current_mentioned_user_ids = Enum.map(rows, & &1.mentioned_user_id) |> Enum.uniq()

    {_count, _deleted} =
      repo.delete_all(from mention in Mention, where: mention.message_id == ^message.id)

    if rows != [] do
      {_count, _mentions} = repo.insert_all(Mention, rows)
    end

    mentions =
      Mention
      |> where([mention], mention.message_id == ^message.id)
      |> order_by([mention], asc: mention.start_offset)
      |> repo.all()

    {:ok,
     %{
       mentions: mentions,
       newly_mentioned_user_ids: current_mentioned_user_ids -- previous_mentioned_user_ids,
       removed_mentioned_user_ids: previous_mentioned_user_ids -- current_mentioned_user_ids
     }}
  end

  defp mentionable_users_by_handle(_repo, _room_id, []), do: %{}

  defp mentionable_users_by_handle(repo, room_id, handles) do
    User
    |> join(:inner, [user], membership in RoomMember, on: membership.user_id == user.id)
    |> where([_user, membership], membership.room_id == ^room_id)
    |> order_by([user], asc: user.id)
    |> lock("FOR SHARE")
    |> repo.all()
    |> Enum.filter(&MentionParser.mentionable?(&1.username))
    |> Enum.group_by(&MentionParser.normalize(&1.username))
    |> Map.take(handles)
    |> Map.new(fn
      {handle, [user]} -> {handle, user}
      {handle, _ambiguous_users} -> {handle, nil}
    end)
  end

  defp broadcast_mentions_created(_broadcaster, _message, []), do: :ok

  defp broadcast_mentions_created(broadcaster, message, mentions) do
    if function_exported?(broadcaster, :broadcast_mentions_created, 2) do
      broadcaster.broadcast_mentions_created(message, mentions)
    else
      :ok
    end
  rescue
    exception ->
      Logger.error("mention broadcast failed",
        message_id: message.id,
        error: Exception.message(exception)
      )

      :ok
  catch
    :exit, reason ->
      Logger.error("mention broadcast failed",
        message_id: message.id,
        error: inspect(reason)
      )

      :ok
  end

  defp broadcast_message_created(broadcaster, room_id, message) do
    broadcaster.broadcast_message_created(room_id, message)
  rescue
    exception ->
      Logger.error("message broadcast failed",
        room_id: room_id,
        message_id: message.id,
        error: Exception.message(exception)
      )

      :ok
  catch
    :exit, reason ->
      Logger.error("message broadcast failed",
        room_id: room_id,
        message_id: message.id,
        error: inspect(reason)
      )

      :ok
  end

  defp authorized_existing_client_message(nil, _user_id, _room_id, _attrs), do: :not_found

  defp authorized_existing_client_message(client_id, user_id, room_id, attrs) do
    Repo.transaction(fn ->
      case authorize_sender(Repo, user_id, room_id) do
        {:ok, :authorized} -> existing_client_message(Repo, client_id, user_id, room_id, attrs)
        {:error, :forbidden} -> {:error, :forbidden}
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, _reason} -> {:error, :forbidden}
    end
  end

  defp existing_client_message(repo, client_id, user_id, room_id, attrs) do
    client_id
    |> then(&repo.get_by(Message, client_id: &1))
    |> repo.preload([:user, :mentions, :attachments])
    |> classify_existing_message(user_id, room_id, attrs)
  end

  defp classify_existing_message(nil, _user_id, _room_id, _attrs), do: :not_found

  defp classify_existing_message(
         %{user_id: user_id, room_id: room_id, deleted_at: nil, content: content} = message,
         user_id,
         room_id,
         %{"content" => content}
       ),
       do: {:ok, message}

  defp classify_existing_message(
         %{user_id: user_id, room_id: room_id, deleted_at: nil, content: content} = message,
         user_id,
         room_id,
         %{content: content}
       ),
       do: {:ok, message}

  defp classify_existing_message(_message, _user_id, _room_id, _attrs),
    do: {:error, :client_id_conflict}

  defp maybe_put_client_id(changeset, nil), do: changeset

  defp maybe_put_client_id(changeset, client_id) do
    Ecto.Changeset.put_change(changeset, :client_id, client_id)
  end

  def delete_message(%Message{} = message) do
    deleted_at = DateTime.utc_now()

    Multi.new()
    |> Multi.run(:mentioned_user_ids, fn repo, _changes ->
      mentioned_user_ids =
        Mention
        |> where([mention], mention.message_id == ^message.id)
        |> select([mention], mention.mentioned_user_id)
        |> distinct(true)
        |> repo.all()

      {:ok, mentioned_user_ids}
    end)
    |> Multi.update(
      :message,
      Ecto.Changeset.change(message, deleted_at: deleted_at),
      allow_stale: true
    )
    |> Multi.run(:room_exists, fn _repo, _changes ->
      {:ok, Rooms.get_room(message.room_id) != nil}
    end)
    |> Repo.transaction()
    |> case do
      {:ok,
       %{message: deleted_message, room_exists: true, mentioned_user_ids: mentioned_user_ids}} ->
        Chat.Broadcaster.broadcast_message_deleted(message.room_id, message.id)
        Chat.Broadcaster.broadcast_mentions_deleted(message, mentioned_user_ids)
        {:ok, deleted_message}

      {:ok,
       %{message: deleted_message, room_exists: false, mentioned_user_ids: mentioned_user_ids}} ->
        Chat.Broadcaster.broadcast_mentions_deleted(message, mentioned_user_ids)
        {:ok, deleted_message}

      {:error, _operation, changeset, _changes} ->
        {:error, changeset}
    end
  end

  def get_room_messages_count(room_id) do
    active_messages()
    |> where([m], m.room_id == ^room_id)
    |> Repo.aggregate(:count)
  end

  def mark_as_read(message_id, user_id) do
    result =
      %ReadReceipt{}
      |> ReadReceipt.changeset(%{message_id: message_id, user_id: user_id})
      |> Repo.insert()

    case result do
      {:ok, _} ->
        :ok

      {:error, %{errors: errors} = changeset} ->
        already_read_error?(errors, changeset)
    end
  end

  defp already_read_error?(errors, changeset) do
    if Enum.any?(errors, fn {field, _} -> field == :user_id end) do
      :already_read
    else
      {:error, changeset}
    end
  end

  def mark_as_read_bulk(message_ids, user_id) when is_list(message_ids) do
    insert_read_receipts(message_ids, user_id)
  end

  def mark_room_messages_as_read(message_ids, user_id, room_id) when is_list(message_ids) do
    readable_message_ids =
      active_messages()
      |> where([message], message.id in ^message_ids)
      |> where([message], message.room_id == ^room_id and message.user_id != ^user_id)
      |> select([message], message.id)
      |> Repo.all()

    case insert_read_receipts(readable_message_ids, user_id, returning: [:message_id]) do
      {_count, inserted_receipts} when is_list(inserted_receipts) ->
        Enum.map(inserted_receipts, & &1.message_id)

      {_count, nil} ->
        []
    end
  end

  @doc "Atomically records room receipts and advances the cursor under membership lock."
  def mark_room_read(message_ids, user_id, room_id) when is_list(message_ids) do
    Rooms.with_membership(user_id, room_id, fn _membership ->
      inserted_ids = mark_room_messages_as_read(message_ids, user_id, room_id)

      case advance_room_read_position(user_id, room_id, message_ids) do
        {:ok, _position} -> {inserted_ids, true}
        {:error, _reason} -> Repo.rollback(:read_position_not_advanced)
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, _reason} -> {[], false}
    end
  end

  def unread_counts_by_room(_user_id, []), do: %{}

  def unread_counts_by_room(user_id, room_ids) when is_list(room_ids) do
    Message
    |> join(:inner, [message], membership in RoomMember,
      on: membership.room_id == message.room_id and membership.user_id == ^user_id
    )
    |> join(:left, [message, _membership], position in RoomReadPosition,
      on: position.room_id == message.room_id and position.user_id == ^user_id
    )
    |> where([message], message.room_id in ^room_ids)
    |> where([message], message.user_id != ^user_id and is_nil(message.deleted_at))
    |> where(
      [message, _membership, position],
      is_nil(position.id) or
        message.inserted_at > position.last_read_message_inserted_at or
        (message.inserted_at == position.last_read_message_inserted_at and
           message.id > position.last_read_message_id)
    )
    |> group_by([message], message.room_id)
    |> select([message], {message.room_id, count(message.id)})
    |> Repo.all()
    |> Map.new()
  end

  def advance_room_read_position(user_id, room_id, message_ids) when is_list(message_ids) do
    case newest_member_message(user_id, room_id, message_ids) do
      nil -> {:error, :not_found}
      message -> upsert_room_read_position(user_id, room_id, message)
    end
  end

  def advance_room_delivery_position(user_id, room_id, message_ids) when is_list(message_ids) do
    case newest_deliverable_message(user_id, room_id, message_ids) do
      nil -> {:error, :not_found}
      message -> upsert_room_delivery_position(user_id, room_id, message)
    end
  end

  def delivery_count(message_id, sender_id) do
    RoomDeliveryPosition
    |> join(:inner, [position], message in Message,
      on: message.id == ^message_id and message.room_id == position.room_id
    )
    |> where(
      [position, message],
      position.user_id != ^sender_id and
        (position.last_delivered_message_inserted_at > message.inserted_at or
           (position.last_delivered_message_inserted_at == message.inserted_at and
              position.last_delivered_message_id >= message.id))
    )
    |> Repo.aggregate(:count)
  end

  def load_delivery_metadata(messages) when is_list(messages) do
    message_ids = Enum.map(messages, & &1.id)

    delivery_counts_by_message =
      RoomDeliveryPosition
      |> join(:inner, [position], message in Message,
        on: message.room_id == position.room_id and message.id in ^message_ids
      )
      |> where(
        [position, message],
        position.user_id != message.user_id and
          (position.last_delivered_message_inserted_at > message.inserted_at or
             (position.last_delivered_message_inserted_at == message.inserted_at and
                position.last_delivered_message_id >= message.id))
      )
      |> group_by([_position, message], message.id)
      |> select([position, message], {message.id, count(position.user_id)})
      |> Repo.all()
      |> Map.new()

    Enum.map(messages, fn message ->
      %{message | delivered_count: Map.get(delivery_counts_by_message, message.id, 0)}
    end)
  end

  defp newest_member_message(user_id, room_id, message_ids) do
    Message
    |> join(:inner, [message], membership in RoomMember,
      on: membership.room_id == message.room_id and membership.user_id == ^user_id
    )
    |> where(
      [message],
      message.room_id == ^room_id and message.id in ^message_ids and is_nil(message.deleted_at)
    )
    |> order_by([message], desc: message.inserted_at, desc: message.id)
    |> limit(1)
    |> Repo.one()
  end

  defp newest_deliverable_message(user_id, room_id, message_ids) do
    Message
    |> join(:inner, [message], membership in RoomMember,
      on: membership.room_id == message.room_id and membership.user_id == ^user_id
    )
    |> where(
      [message],
      message.room_id == ^room_id and message.id in ^message_ids and message.user_id != ^user_id and
        is_nil(message.deleted_at)
    )
    |> order_by([message], desc: message.inserted_at, desc: message.id)
    |> limit(1)
    |> Repo.one()
  end

  defp upsert_room_read_position(user_id, room_id, message) do
    now = DateTime.utc_now()

    position = %RoomReadPosition{
      user_id: user_id,
      room_id: room_id,
      last_read_message_id: message.id,
      last_read_message_inserted_at: message.inserted_at,
      last_read_at: now
    }

    on_conflict =
      from(existing in RoomReadPosition,
        update: [
          set: [
            last_read_message_id: ^message.id,
            last_read_message_inserted_at: ^message.inserted_at,
            last_read_at: ^now,
            updated_at: ^now
          ]
        ],
        where:
          existing.last_read_message_inserted_at < ^message.inserted_at or
            (existing.last_read_message_inserted_at == ^message.inserted_at and
               existing.last_read_message_id < ^message.id)
      )

    with {:ok, _position} <-
           Repo.insert(position,
             on_conflict: on_conflict,
             conflict_target: [:user_id, :room_id],
             allow_stale: true
           ) do
      {:ok, Repo.get_by!(RoomReadPosition, user_id: user_id, room_id: room_id)}
    end
  end

  defp upsert_room_delivery_position(user_id, room_id, message) do
    now = DateTime.utc_now()

    position = %RoomDeliveryPosition{
      user_id: user_id,
      room_id: room_id,
      last_delivered_message_id: message.id,
      last_delivered_message_inserted_at: message.inserted_at,
      last_delivered_at: now
    }

    on_conflict =
      from(existing in RoomDeliveryPosition,
        update: [
          set: [
            last_delivered_message_id: ^message.id,
            last_delivered_message_inserted_at: ^message.inserted_at,
            last_delivered_at: ^now,
            updated_at: ^now
          ]
        ],
        where:
          existing.last_delivered_message_inserted_at < ^message.inserted_at or
            (existing.last_delivered_message_inserted_at == ^message.inserted_at and
               existing.last_delivered_message_id < ^message.id)
      )

    with {:ok, _position} <-
           Repo.insert(position,
             on_conflict: on_conflict,
             conflict_target: [:user_id, :room_id],
             allow_stale: true
           ) do
      {:ok, Repo.get_by!(RoomDeliveryPosition, user_id: user_id, room_id: room_id)}
    end
  end

  defp insert_read_receipts(message_ids, user_id, opts \\ []) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    entries =
      Enum.map(message_ids, fn msg_id ->
        %{
          message_id: msg_id,
          user_id: user_id,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(
      ReadReceipt,
      entries,
      on_conflict: :nothing,
      conflict_target: [:user_id, :message_id],
      returning: Keyword.get(opts, :returning, false)
    )
  end

  def someone_read?(message_id, sender_id) do
    read_receipt_exists?(message_id, sender_id) or read_position_reached?(message_id, sender_id)
  end

  defp read_receipt_exists?(message_id, sender_id) do
    ReadReceipt
    |> where([rr], rr.message_id == ^message_id and rr.user_id != ^sender_id)
    |> Repo.exists?()
  end

  defp read_position_reached?(message_id, sender_id) do
    RoomReadPosition
    |> join(:inner, [position], message in Message,
      on: message.id == ^message_id and message.room_id == position.room_id
    )
    |> where(
      [position, message],
      position.user_id != ^sender_id and
        (position.last_read_message_inserted_at > message.inserted_at or
           (position.last_read_message_inserted_at == message.inserted_at and
              position.last_read_message_id >= message.id))
    )
    |> Repo.exists?()
  end

  def read_count(message_id, _sender_id) do
    [message_id]
    |> reader_names_by_message()
    |> Map.get(message_id, [])
    |> length()
  end

  def load_read_metadata(messages) when is_list(messages) do
    message_ids = Enum.map(messages, & &1.id)
    readers_by_message = reader_names_by_message(message_ids)

    Enum.map(messages, fn message ->
      reader_names = Map.get(readers_by_message, message.id, [])
      %{message | read_count: length(reader_names), reader_names: reader_names}
    end)
  end

  defp reader_names_by_message(message_ids) when is_list(message_ids) do
    receipt_readers_query =
      ReadReceipt
      |> join(:inner, [receipt], message in Message, on: message.id == receipt.message_id)
      |> join(:inner, [receipt, _message], user in assoc(receipt, :user))
      |> where(
        [receipt, message, _user],
        receipt.message_id in ^message_ids and receipt.user_id != message.user_id
      )
      |> select([receipt, _message, user], %{
        message_id: receipt.message_id,
        user_id: user.id,
        username: user.username
      })

    position_readers_query =
      RoomReadPosition
      |> join(:inner, [position], message in Message,
        on: message.room_id == position.room_id and message.id in ^message_ids
      )
      |> join(:inner, [position, _message], user in User, on: user.id == position.user_id)
      |> where(
        [position, message, _user],
        position.user_id != message.user_id and
          (position.last_read_message_inserted_at > message.inserted_at or
             (position.last_read_message_inserted_at == message.inserted_at and
                position.last_read_message_id >= message.id))
      )
      |> select([_position, message, user], %{
        message_id: message.id,
        user_id: user.id,
        username: user.username
      })

    readers =
      from(reader in subquery(receipt_readers_query |> union_all(^position_readers_query)),
        order_by: [asc: reader.message_id, asc: reader.user_id],
        select: {reader.message_id, reader.user_id, reader.username}
      )
      |> Repo.all()

    readers
    |> Enum.group_by(&elem(&1, 0))
    |> Map.new(fn {message_id, readers} ->
      reader_names =
        readers
        |> Enum.uniq_by(&elem(&1, 1))
        |> Enum.map(&elem(&1, 2))

      {message_id, reader_names}
    end)
  end

  def list_readers(message_id) do
    ReadReceipt
    |> where([rr], rr.message_id == ^message_id)
    |> preload(:user)
    |> order_by([rr], asc: rr.inserted_at)
    |> Repo.all()
    |> Enum.map(fn rr ->
      %{
        user_id: rr.user_id,
        username: rr.user.username,
        read_at: rr.inserted_at
      }
    end)
  end

  def delete_message_if_unread(%Message{} = message, sender_id) do
    if someone_read?(message.id, sender_id) do
      {:error, :already_read}
    else
      delete_message(message)
    end
  end

  def delete_own_unread_message(message_id, user_id, room_id) do
    case get_message(message_id) do
      nil ->
        {:error, :not_found}

      %Message{room_id: message_room_id} when message_room_id != room_id ->
        {:error, :not_found}

      %Message{} = message ->
        cond do
          not Rooms.room_member?(user_id, room_id) ->
            {:error, :not_member}

          message.user_id != user_id ->
            {:error, :not_authorized}

          true ->
            delete_message_if_unread(message, user_id)
        end
    end
  end

  @doc """
  Edits the content of a message as its author.

  Only the author of an active (non-deleted) message in the given room can
  edit it. The edit records `edited_at`, reconciles persisted mentions with
  the new content, and broadcasts the updated message and any mention changes
  through PubSub. Editing with unchanged content is a no-op that neither
  records a timestamp nor broadcasts.
  """
  def edit_own_message(message_id, user_id, room_id, attrs, opts \\ []) do
    case get_message(message_id) do
      nil ->
        {:error, :not_found}

      %Message{room_id: message_room_id} when message_room_id != room_id ->
        {:error, :not_found}

      %Message{} = message ->
        cond do
          not Rooms.room_member?(user_id, room_id) ->
            {:error, :not_member}

          message.user_id != user_id ->
            {:error, :not_authorized}

          true ->
            update_message(
              message,
              attrs,
              Keyword.get(opts, :broadcaster, Chat.Broadcaster)
            )
        end
    end
  end

  defp update_message(%Message{content: content} = message, attrs, broadcaster) do
    new_content = Map.get(attrs, "content", Map.get(attrs, :content))

    if new_content == content do
      {:ok, message}
    else
      changeset =
        message
        |> Message.changeset(attrs)
        |> Ecto.Changeset.put_change(:edited_at, DateTime.utc_now())

      Multi.new()
      |> Multi.run(:locked_room, fn repo, _changes ->
        lock_room_for_mentions(repo, message.room_id)
      end)
      |> Multi.insert(:revision, revision_changeset(message))
      |> Multi.update(:message, changeset, allow_stale: true)
      |> Multi.run(:mention_reconciliation, fn repo, %{message: updated_message} ->
        reconcile_mentions(repo, updated_message)
      end)
      |> Multi.run(:message_with_user, &fetch_updated_message/2)
      |> Repo.transaction()
      |> case do
        {:ok, %{message_with_user: message, mention_reconciliation: reconciliation}} ->
          broadcast_message_updated(broadcaster, message.room_id, message)
          broadcast_mention_changes(broadcaster, message, reconciliation)
          {:ok, message}

        {:error, :message_with_user, :message_deleted, _changes} ->
          {:error, :message_deleted}

        {:error, :locked_room, :forbidden, _changes} ->
          {:error, :forbidden}

        {:error, _operation, changeset, _changes} ->
          {:error, changeset}
      end
    end
  end

  defp revision_changeset(message) do
    %MessageRevision{}
    |> MessageRevision.changeset(%{content: message.content})
    |> Ecto.Changeset.put_change(:message_id, message.id)
    |> Ecto.Changeset.put_change(:editor_id, message.user_id)
    |> Ecto.Changeset.validate_required([:message_id, :editor_id])
  end

  defp fetch_updated_message(repo, %{message: updated_message}) do
    case repo.one(
           from m in Message,
             where: m.id == ^updated_message.id,
             preload: [:user, :mentions, :attachments]
         ) do
      nil -> {:error, :message_deleted}
      message_with_user -> {:ok, message_with_user}
    end
  end

  defp broadcast_message_updated(broadcaster, room_id, message) do
    broadcaster.broadcast_message_updated(room_id, message)
  rescue
    exception ->
      Logger.error("message broadcast failed",
        room_id: room_id,
        message_id: message.id,
        error: Exception.message(exception)
      )

      :ok
  catch
    :exit, reason ->
      Logger.error("message broadcast failed",
        room_id: room_id,
        message_id: message.id,
        error: inspect(reason)
      )

      :ok
  end

  defp broadcast_mention_changes(
         _broadcaster,
         _message,
         %{newly_mentioned_user_ids: [], removed_mentioned_user_ids: []}
       ),
       do: :ok

  defp broadcast_mention_changes(broadcaster, message, %{
         newly_mentioned_user_ids: newly,
         removed_mentioned_user_ids: removed
       }) do
    newly_mentions = Enum.filter(message.mentions, &(&1.mentioned_user_id in newly))

    if newly_mentions != [] do
      broadcast_mentions_created(broadcaster, message, newly_mentions)
    end

    if removed != [] do
      Chat.Broadcaster.broadcast_mentions_deleted(message, removed)
    end

    :ok
  end

  def delivery_status(message_id, sender_id, online_user_ids) do
    if someone_read?(message_id, sender_id) do
      :read
    else
      other_online_user_ids = Enum.reject(online_user_ids, &(&1 == sender_id))

      if other_online_user_ids != [] do
        :delivered
      else
        :sent
      end
    end
  end

  def message_status(read_count, delivered_count) do
    cond do
      read_count > 0 -> :read
      delivered_count > 0 -> :delivered
      true -> :sent
    end
  end

  def readers_tooltip(message_id, sender_id, delivered_count) do
    readers = list_readers(message_id)
    other_readers = Enum.reject(readers, &(&1.user_id == sender_id))

    cond do
      other_readers == [] and delivered_count == 0 ->
        "Enviada"

      other_readers == [] ->
        "Entregue a #{delivered_count} pessoa(s)"

      true ->
        names = Enum.map_join(other_readers, ", ", & &1.username)
        "Lida por: #{names}"
    end
  end

  defp active_messages do
    where(Message, [m], is_nil(m.deleted_at))
  end
end
