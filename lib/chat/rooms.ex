defmodule Chat.Rooms do
  @moduledoc "Room lifecycle, membership, search, and authorization operations."

  import Ecto.Query

  alias Chat.Accounts.User
  alias Chat.Messages.MentionParser
  alias Chat.Messages.Message
  alias Chat.Repo
  alias Chat.Rooms.{MembershipCache, Room, RoomMember}
  alias Ecto.Multi

  @available_room_limit 50

  def list_rooms do
    Repo.all(Room)
  end

  @spec list_available_rooms(any(), binary()) :: any()
  def list_available_rooms(user_id, query \\ "") do
    pattern = "%#{escape_search(query)}%"

    Room
    |> join(:left, [room], membership in RoomMember,
      on: membership.room_id == room.id and membership.user_id == ^user_id
    )
    |> where([_room, membership], is_nil(membership.id))
    |> where(
      [room, _membership],
      ilike(room.name, ^pattern) or ilike(coalesce(room.description, ""), ^pattern)
    )
    |> order_by([room], asc: room.name)
    |> select([room, _membership], struct(room, [:id, :name, :description]))
    |> limit(^@available_room_limit)
    |> Repo.all()
  end

  defp escape_search(query) do
    query
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  def get_room(id) do
    Repo.get(Room, id)
  end

  def get_room!(id) do
    Repo.get!(Room, id)
  end

  def fetch_member_room(user_id, room_id) do
    query =
      from r in Room,
        where: r.id == ^room_id,
        left_join: rm in RoomMember,
        on: rm.room_id == r.id and rm.user_id == ^user_id,
        select: {r, not is_nil(rm.id)}

    case Repo.one(query) do
      nil -> {:error, :not_found}
      {room, true} -> {:ok, room}
      {_room, false} -> {:error, :forbidden}
    end
  end

  @doc "Runs a room operation while holding the current membership under a shared lock."
  def with_member_room(user_id, room_id, operation) when is_function(operation, 1) do
    with_membership(user_id, room_id, fn membership ->
      membership
      |> Repo.preload(room: [:creator, :members])
      |> Map.fetch!(:room)
      |> operation.()
    end)
  end

  @doc "Runs an operation while holding a persisted membership under a shared lock."
  def with_membership(user_id, room_id, operation) when is_function(operation, 1) do
    with {:ok, user_id} <- Ecto.UUID.cast(user_id),
         {:ok, room_id} <- Ecto.UUID.cast(room_id) do
      Repo.transaction(fn -> run_membership_operation(user_id, room_id, operation) end)
    else
      :error -> {:error, :invalid_id}
    end
  end

  defp run_membership_operation(user_id, room_id, operation) do
    case locked_membership(user_id, room_id) do
      {:ok, membership} -> operation.(membership)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp locked_membership(user_id, room_id) do
    with %Room{} <- locked_room(room_id),
         %RoomMember{} = membership <- locked_room_membership(user_id, room_id) do
      {:ok, membership}
    else
      nil -> {:error, :not_found}
      :not_member -> {:error, :forbidden}
    end
  end

  defp locked_room(room_id) do
    Room
    |> where([room], room.id == ^room_id)
    |> lock("FOR SHARE")
    |> Repo.one()
  end

  defp locked_room_membership(user_id, room_id) do
    RoomMember
    |> where([membership], membership.user_id == ^user_id and membership.room_id == ^room_id)
    |> lock("FOR SHARE")
    |> Repo.one()
    |> case do
      nil -> :not_member
      membership -> membership
    end
  end

  def create_room(attrs, creator_id) do
    room_changeset =
      %Room{}
      |> Room.changeset(attrs)
      |> Ecto.Changeset.put_change(:creator_id, creator_id)

    Multi.new()
    |> Multi.insert(:room, room_changeset)
    |> Multi.insert(:membership, fn %{room: room} ->
      RoomMember.changeset(%RoomMember{}, %{user_id: creator_id, room_id: room.id})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{room: room}} -> {:ok, room}
      {:error, _operation, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Opens the single treatment room associated with an order.

  The room is created automatically on first access and reused afterward.
  """
  def open_order_room(order_id, user_id) when is_integer(order_id) do
    case Repo.get_by(Room, order_id: order_id) do
      nil -> create_order_room(order_id, user_id)
      room -> ensure_order_room_membership(room, user_id)
    end
  end

  defp create_order_room(order_id, user_id) do
    attrs = %{
      "name" => "Pedido ##{order_id}",
      "description" => "Sala de tratativa do pedido #{order_id}",
      "order_id" => order_id
    }

    case create_room(attrs, user_id) do
      {:ok, room} ->
        {:ok, Repo.preload(room, [:creator, :members])}

      {:error, %Ecto.Changeset{} = changeset} ->
        recover_order_room_creation(changeset, order_id, user_id)
    end
  end

  defp recover_order_room_creation(%{errors: errors} = changeset, order_id, user_id) do
    if Keyword.has_key?(errors, :order_id) do
      open_existing_order_room(order_id, user_id, changeset)
    else
      {:error, changeset}
    end
  end

  defp open_existing_order_room(order_id, user_id, changeset) do
    case Repo.get_by(Room, order_id: order_id) do
      nil -> {:error, changeset}
      room -> ensure_order_room_membership(room, user_id)
    end
  end

  defp ensure_order_room_membership(room, user_id) do
    case join_room(user_id, room.id) do
      {:ok, _membership} -> {:ok, Repo.preload(room, [:creator, :members])}
      {:error, reason} -> {:error, reason}
    end
  end

  def update_room(%Room{} = room, attrs) do
    room
    |> Room.changeset(attrs)
    |> Repo.update()
  end

  def delete_room(%Room{} = room) do
    member_ids_query =
      from membership in RoomMember,
        where: membership.room_id == ^room.id,
        select: membership.user_id,
        lock: "FOR SHARE"

    Multi.new()
    |> Multi.run(:locked_room, fn repo, _changes -> lock_room_for_update(repo, room.id) end)
    |> Multi.all(:member_ids, member_ids_query)
    |> Multi.delete(:room, room)
    |> Repo.transaction()
    |> case do
      {:ok, %{room: deleted_room, member_ids: member_ids}} ->
        Enum.each(member_ids, &MembershipCache.put(&1, room.id, false))
        Chat.Broadcaster.broadcast_room_deleted(room.id, member_ids)
        {:ok, deleted_room}

      {:error, _operation, changeset, _changes} ->
        {:error, changeset}
    end
  end

  def join_room(user_id, room_id) do
    Multi.new()
    |> Multi.run(:locked_room, fn repo, _changes -> lock_room_for_update(repo, room_id) end)
    |> Multi.run(:locked_user, fn repo, _changes -> lock_user_for_membership(repo, user_id) end)
    |> Multi.insert(
      :membership,
      fn _changes ->
        RoomMember.changeset(%RoomMember{}, %{user_id: user_id, room_id: room_id})
      end,
      on_conflict: :nothing,
      conflict_target: [:user_id, :room_id]
    )
    |> Multi.run(:persisted_membership, fn repo, _changes ->
      case repo.get_by(RoomMember, user_id: user_id, room_id: room_id) do
        %RoomMember{} = membership -> {:ok, membership}
        nil -> {:error, :membership_not_persisted}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{persisted_membership: membership}} ->
        MembershipCache.put(user_id, room_id, true)
        {:ok, membership}

      {:error, :locked_room, :not_found, _changes} ->
        {:error, :not_found}

      {:error, :locked_user, :not_found, _changes} ->
        {:error, :not_found}

      {:error, _operation, reason, _changes} ->
        {:error, reason}
    end
  end

  defp lock_room_for_update(repo, room_id) do
    query = from room in Room, where: room.id == ^room_id, lock: "FOR UPDATE"

    case repo.one(query) do
      %Room{} = room -> {:ok, room}
      nil -> {:error, :not_found}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  defp lock_user_for_membership(repo, user_id) do
    query = from user in User, where: user.id == ^user_id, lock: "FOR SHARE"

    case repo.one(query) do
      %User{} = user -> {:ok, user}
      nil -> {:error, :not_found}
    end
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  @doc "Fixa uma sala para o membro informado."
  @spec pin_room(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, RoomMember.t()}
          | {:error, :invalid_room_id | :invalid_user_id | :not_member}
  def pin_room(user_id, room_id) do
    update_pin(user_id, room_id, DateTime.utc_now())
  end

  @doc "Remove a fixação de uma sala para o membro informado."
  @spec unpin_room(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, RoomMember.t()}
          | {:error, :invalid_room_id | :invalid_user_id | :not_member}
  def unpin_room(user_id, room_id) do
    update_pin(user_id, room_id, nil)
  end

  def leave_room(user_id, room_id) do
    case get_room(room_id) do
      nil ->
        {:error, :not_found}

      room ->
        cond do
          not room_member?(user_id, room_id) ->
            {:error, :not_member}

          room.creator_id == user_id ->
            {:error, :creator_cannot_leave}

          true ->
            {count, _} =
              RoomMember
              |> where([rm], rm.user_id == ^user_id and rm.room_id == ^room_id)
              |> Repo.delete_all()

            MembershipCache.put(user_id, room_id, false)
            Chat.Broadcaster.broadcast_membership_left(user_id, room_id)
            {:ok, count}
        end
    end
  end

  def get_room_members(room_id) do
    RoomMember
    |> where([rm], rm.room_id == ^room_id)
    |> preload(:user)
    |> Repo.all()
    |> Enum.map(& &1.user)
  end

  @doc "Searches mention candidates among members of one room."
  def search_room_members(room_id, query, requester_id, opts \\ [])

  def search_room_members(room_id, query, requester_id, opts) when is_binary(query) do
    with {:ok, room_id} <- Ecto.UUID.cast(room_id),
         {:ok, requester_id} <- Ecto.UUID.cast(requester_id),
         {:ok, excluded_user_id} <- cast_optional_uuid(Keyword.get(opts, :exclude_user_id)) do
      limit = mention_search_limit(Keyword.get(opts, :limit, 10))
      normalized_query = query |> String.slice(0, 50) |> MentionParser.normalize()

      mention_candidates(room_id, requester_id)
      |> Enum.filter(&MentionParser.mentionable?(&1.username))
      |> Enum.group_by(&MentionParser.normalize(&1.username))
      |> Enum.flat_map(fn
        {_handle, [user]} -> [user]
        {_handle, _ambiguous_users} -> []
      end)
      |> Enum.reject(&(&1.id == excluded_user_id))
      |> Enum.filter(fn user ->
        user.username
        |> MentionParser.normalize()
        |> String.contains?(normalized_query)
      end)
      |> Enum.sort_by(&MentionParser.normalize(&1.username))
      |> Enum.take(limit)
    else
      :error -> []
    end
  end

  def search_room_members(_room_id, _query, _requester_id, _opts), do: []

  defp mention_candidates(room_id, requester_id) do
    User
    |> join(:inner, [user], membership in RoomMember, on: membership.user_id == user.id)
    |> join(:inner, [_user, membership], requester_membership in RoomMember,
      on:
        requester_membership.room_id == membership.room_id and
          requester_membership.user_id == ^requester_id
    )
    |> where([_user, membership], membership.room_id == ^room_id)
    |> Repo.all()
  end

  def get_user_rooms(user_id) do
    latest_message =
      from(message in Message,
        where: message.room_id == parent_as(:room).id,
        where: is_nil(message.deleted_at),
        order_by: [desc: message.inserted_at],
        limit: 1,
        select: %{content: message.content}
      )

    # NOTE: members are deliberately NOT joined here. Joining a many_to_many
    # association multiplies result rows by member count and makes the LATERAL
    # last-message subquery run once per (room x member) row. Members are
    # preloaded afterwards in a single batched query, so the total stays at 2
    # SELECTs regardless of how many members each room has (no N+1).
    from(r in Room,
      as: :room,
      join: rm in RoomMember,
      on: rm.room_id == r.id,
      where: rm.user_id == ^user_id,
      join: c in assoc(r, :creator),
      left_lateral_join: latest in subquery(latest_message),
      on: true,
      order_by: [desc_nulls_last: rm.pinned_at, asc: r.name],
      select_merge: %{pinned_at: rm.pinned_at, last_message_preview: latest.content},
      preload: [creator: c]
    )
    |> Repo.all()
    |> Repo.preload(:members)
  end

  def list_user_order_conversations(user_id, order_ids) when is_list(order_ids) do
    from(room in Room,
      join: membership in RoomMember,
      on: membership.room_id == room.id,
      where: membership.user_id == ^user_id,
      where: room.order_id in ^order_ids,
      select: room
    )
    |> Repo.all()
  end

  def room_member?(user_id, room_id) do
    case MembershipCache.get(user_id, room_id) do
      nil ->
        result =
          RoomMember
          |> where([rm], rm.user_id == ^user_id and rm.room_id == ^room_id)
          |> Repo.exists?()

        MembershipCache.put(user_id, room_id, result)
        result

      result ->
        result
    end
  end

  defp update_pin(user_id, room_id, pinned_at) do
    with {:ok, user_id} <- cast_uuid(user_id, :invalid_user_id),
         {:ok, room_id} <- cast_uuid(room_id, :invalid_room_id) do
      update_membership_pin(user_id, room_id, pinned_at)
    end
  end

  defp cast_uuid(value, error) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, error}
    end
  end

  defp cast_optional_uuid(nil), do: {:ok, nil}
  defp cast_optional_uuid(value), do: Ecto.UUID.cast(value)

  defp mention_search_limit(limit) when is_integer(limit) and limit in 1..20, do: limit
  defp mention_search_limit(_limit), do: 10

  defp update_membership_pin(user_id, room_id, pinned_at) do
    RoomMember
    |> where([membership], membership.user_id == ^user_id and membership.room_id == ^room_id)
    |> select([membership], membership)
    |> Repo.update_all(set: [pinned_at: pinned_at])
    |> case do
      {1, [membership]} -> {:ok, membership}
      {0, []} -> {:error, :not_member}
    end
  end
end
