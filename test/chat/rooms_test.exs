defmodule Chat.RoomsTest do
  use Chat.DataCase, async: false

  alias Chat.Auth.Identity
  alias Chat.Messages
  alias Chat.Repo
  alias Chat.Rooms
  alias Chat.Rooms.RoomMember

  import Ecto.Query

  setup do
    {:ok, owner} = Identity.sync_user(%{"sub" => "room-owner"}, %{})
    {:ok, member} = Identity.sync_user(%{"sub" => "room-member"}, %{})
    %{owner: owner, member: member}
  end

  test "creating a room atomically adds its creator", %{owner: owner} do
    assert {:ok, room} = Rooms.create_room(%{"name" => "Equipe"}, owner.id)
    assert Rooms.room_member?(owner.id, room.id)
  end

  test "opens one automatic treatment room per order", %{owner: owner, member: member} do
    assert {:ok, first_room} = Rooms.open_order_room(9_998_043_469, owner.id)
    assert first_room.order_id == 9_998_043_469
    assert first_room.name == "Pedido #9998043469"

    assert {:ok, second_room} = Rooms.open_order_room(9_998_043_469, member.id)
    assert second_room.id == first_room.id
    assert Rooms.room_member?(member.id, first_room.id)
  end

  test "room names are globally unique", %{owner: owner, member: member} do
    assert {:ok, _room} = Rooms.create_room(%{"name" => "Pedido 123"}, owner.id)

    assert {:error, changeset} = Rooms.create_room(%{"name" => "Pedido 123"}, member.id)
    assert "has already been taken" in errors_on(changeset).name
  end

  test "joining an existing room is idempotent", %{owner: owner, member: member} do
    {:ok, room} = Rooms.create_room(%{"name" => "Equipe"}, owner.id)

    assert {:ok, _membership} = Rooms.join_room(member.id, room.id)
    assert {:ok, _membership} = Rooms.join_room(member.id, room.id)
    assert Enum.count(Rooms.get_room_members(room.id), &(&1.id == member.id)) == 1
  end

  test "member room operation holds membership until its callback completes", %{
    owner: owner,
    member: member
  } do
    {:ok, room} = Rooms.create_room(%{"name" => "Operação autorizada"}, owner.id)
    assert {:ok, _membership} = Rooms.join_room(member.id, room.id)
    supervisor = start_supervised!(Task.Supervisor)
    test_pid = self()

    authorized_task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Rooms.with_member_room(member.id, room.id, fn authorized_room ->
          send(test_pid, {:membership_locked, self()})

          receive do
            :release_membership -> authorized_room.id
          end
        end)
      end)

    assert_receive {:membership_locked, authorized_pid}

    leave_task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        send(test_pid, :leave_started)
        Rooms.leave_room(member.id, room.id)
      end)

    assert_receive :leave_started
    assert Task.yield(leave_task, 50) == nil

    send(authorized_pid, :release_membership)
    assert Task.await(authorized_task) == {:ok, room.id}
    assert Task.await(leave_task) == {:ok, 1}
  end

  test "member room operation creates its first read position before concurrent room deletion", %{
    owner: owner,
    member: member
  } do
    {:ok, room} = Rooms.create_room(%{"name" => "Ordem de locks"}, owner.id)
    assert {:ok, _membership} = Rooms.join_room(member.id, room.id)

    assert {:ok, message} =
             Messages.create_message(%{"content" => "Primeira leitura"}, owner.id, room.id)

    supervisor = start_supervised!(Task.Supervisor)
    test_pid = self()

    authorized_task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        Rooms.with_member_room(member.id, room.id, fn _authorized_room ->
          send(test_pid, {:room_and_membership_locked, self()})

          receive do
            :create_read_position ->
              Messages.advance_room_read_position(member.id, room.id, [message.id])
          end
        end)
      end)

    assert_receive {:room_and_membership_locked, authorized_pid}

    delete_task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        send(test_pid, :room_delete_started)
        Rooms.delete_room(room)
      end)

    assert_receive :room_delete_started
    assert Task.yield(delete_task, 50) == nil

    send(authorized_pid, :create_read_position)
    assert {:ok, {:ok, _position}} = Task.await(authorized_task)
    assert {:ok, deleted_room} = Task.await(delete_task)
    assert deleted_room.id == room.id
  end

  test "deleting a room invalidates cached memberships", %{owner: owner, member: member} do
    {:ok, room} = Rooms.create_room(%{"name" => "Cache descartável"}, owner.id)
    assert {:ok, _membership} = Rooms.join_room(member.id, room.id)

    assert Rooms.room_member?(owner.id, room.id)
    assert Rooms.room_member?(member.id, room.id)
    assert {:ok, _deleted_room} = Rooms.delete_room(room)

    refute Rooms.room_member?(owner.id, room.id)
    refute Rooms.room_member?(member.id, room.id)
  end

  test "mention autocomplete searches only current room members", %{owner: owner, member: member} do
    {:ok, room} = Rooms.create_room(%{"name" => "Autocomplete"}, owner.id)
    assert {:ok, _membership} = Rooms.join_room(member.id, room.id)
    {:ok, outsider} = Identity.sync_user(%{"sub" => "room-member-outsider"}, %{})

    assert [found] =
             Rooms.search_room_members(room.id, "member", owner.id,
               exclude_user_id: owner.id,
               limit: 10
             )

    assert found.id == member.id
    refute found.id == outsider.id
    assert Rooms.search_room_members(room.id, "member", outsider.id) == []
    assert Rooms.search_room_members("not-a-uuid", "member", owner.id) == []
    assert Rooms.search_room_members(room.id, %{}, owner.id) == []
  end

  test "mention autocomplete excludes case-insensitive username collisions", %{owner: owner} do
    {:ok, room} = Rooms.create_room(%{"name" => "Autocomplete ambíguo"}, owner.id)

    {:ok, upper} =
      Identity.sync_user(
        %{"sub" => "case-upper", "email" => "case-upper@example.com", "username" => "CaseTarget"},
        %{}
      )

    {:ok, lower} =
      Identity.sync_user(
        %{"sub" => "case-lower", "email" => "case-lower@example.com", "username" => "casetarget"},
        %{}
      )

    assert {:ok, _membership} = Rooms.join_room(upper.id, room.id)
    assert {:ok, _membership} = Rooms.join_room(lower.id, room.id)

    assert Rooms.search_room_members(room.id, "case", owner.id, exclude_user_id: owner.id) == []
  end

  test "mention autocomplete includes spaced names and excludes the quote delimiter", %{
    owner: owner
  } do
    {:ok, room} = Rooms.create_room(%{"name" => "Autocomplete válido"}, owner.id)

    {:ok, spaced} =
      Identity.sync_user(
        %{
          "sub" => "space-target",
          "email" => "space-target@example.com",
          "username" => "Space Target"
        },
        %{}
      )

    {:ok, unaddressable} =
      Identity.sync_user(
        %{
          "sub" => "quote-target",
          "email" => "quote-target@example.com",
          "username" => ~s(Quote "Target)
        },
        %{}
      )

    assert {:ok, _membership} = Rooms.join_room(spaced.id, room.id)
    assert {:ok, _membership} = Rooms.join_room(unaddressable.id, room.id)

    assert [candidate] =
             Rooms.search_room_members(room.id, "space", owner.id, exclude_user_id: owner.id)

    assert candidate.id == spaced.id
    assert Rooms.search_room_members(room.id, "quote", owner.id, exclude_user_id: owner.id) == []
  end

  test "mention autocomplete normalizes Unicode independently from database collation", %{
    owner: owner
  } do
    {:ok, room} = Rooms.create_room(%{"name" => "Autocomplete Unicode"}, owner.id)

    {:ok, member} =
      Identity.sync_user(
        %{
          "sub" => "unicode-normalization-target",
          "email" => "unicode-normalization-target@example.com",
          "username" => "José da Silva"
        },
        %{}
      )

    assert {:ok, _membership} = Rooms.join_room(member.id, room.id)
    decomposed_query = String.normalize("JOSÉ", :nfd)

    assert [candidate] =
             Rooms.search_room_members(room.id, decomposed_query, owner.id,
               exclude_user_id: owner.id
             )

    assert candidate.id == member.id
  end

  test "the creator cannot leave their own room", %{owner: owner} do
    {:ok, room} = Rooms.create_room(%{"name" => "Equipe"}, owner.id)

    assert {:error, :creator_cannot_leave} = Rooms.leave_room(owner.id, room.id)
    assert Rooms.room_member?(owner.id, room.id)
  end

  test "a member can leave a room", %{owner: owner, member: member} do
    {:ok, room} = Rooms.create_room(%{"name" => "Equipe"}, owner.id)
    assert {:ok, _membership} = Rooms.join_room(member.id, room.id)

    assert {:ok, 1} = Rooms.leave_room(member.id, room.id)
    refute Rooms.room_member?(member.id, room.id)
  end

  test "a member can pin a room for themselves", %{owner: owner, member: member} do
    {:ok, room} = Rooms.create_room(%{"name" => "Fixada"}, owner.id)
    assert {:ok, _membership} = Rooms.join_room(member.id, room.id)

    assert {:ok, %RoomMember{pinned_at: %DateTime{}}} = Rooms.pin_room(member.id, room.id)

    membership = Repo.get_by!(RoomMember, user_id: member.id, room_id: room.id)
    assert %DateTime{} = membership.pinned_at

    owner_membership = Repo.get_by!(RoomMember, user_id: owner.id, room_id: room.id)
    assert is_nil(owner_membership.pinned_at)
  end

  test "a member can unpin their room", %{owner: owner} do
    {:ok, room} = Rooms.create_room(%{"name" => "Temporariamente fixada"}, owner.id)
    assert {:ok, %RoomMember{pinned_at: %DateTime{}}} = Rooms.pin_room(owner.id, room.id)

    assert {:ok, %RoomMember{pinned_at: nil}} = Rooms.unpin_room(owner.id, room.id)

    membership = Repo.get_by!(RoomMember, user_id: owner.id, room_id: room.id)
    assert is_nil(membership.pinned_at)
  end

  test "a non-member cannot pin a room", %{owner: owner, member: member} do
    {:ok, room} = Rooms.create_room(%{"name" => "Privada"}, owner.id)

    assert {:error, :not_member} = Rooms.pin_room(member.id, room.id)
  end

  test "pin rejects a malformed room id", %{owner: owner} do
    assert {:error, :invalid_room_id} = Rooms.pin_room(owner.id, "not-a-uuid")
  end

  test "unpin rejects a malformed room id", %{owner: owner} do
    assert {:error, :invalid_room_id} = Rooms.unpin_room(owner.id, "not-a-uuid")
  end

  test "pin rejects a malformed user id" do
    assert {:error, :invalid_user_id} = Rooms.pin_room("not-a-uuid", Ecto.UUID.generate())
  end

  test "a non-member cannot unpin a room", %{owner: owner, member: member} do
    {:ok, room} = Rooms.create_room(%{"name" => "Fixação privada"}, owner.id)
    assert {:ok, _membership} = Rooms.pin_room(owner.id, room.id)

    assert {:error, :not_member} = Rooms.unpin_room(member.id, room.id)
  end

  test "a non-member cannot leave a room", %{owner: owner, member: member} do
    {:ok, room} = Rooms.create_room(%{"name" => "Equipe"}, owner.id)

    assert {:error, :not_member} = Rooms.leave_room(member.id, room.id)
  end

  test "creator removed manually is treated as non-member", %{owner: owner} do
    {:ok, room} = Rooms.create_room(%{"name" => "Equipe"}, owner.id)

    # Simulate inconsistent data: admin removes creator from room_members manually.
    RoomMember
    |> where([rm], rm.user_id == ^owner.id and rm.room_id == ^room.id)
    |> Repo.delete_all()

    refute Rooms.room_member?(owner.id, room.id)
    assert {:error, :not_member} = Rooms.leave_room(owner.id, room.id)
  end

  test "joining a non-existent room returns not_found", %{member: member} do
    non_existent_room_id = Ecto.UUID.generate()

    assert {:error, :not_found} = Rooms.join_room(member.id, non_existent_room_id)
    refute Rooms.room_member?(member.id, non_existent_room_id)
  end

  test "get_user_rooms/1 preloads members to avoid N+1 in sidebar", %{
    owner: owner,
    member: member
  } do
    {:ok, room} = Rooms.create_room(%{"name" => "Members Preloaded"}, owner.id)
    {:ok, _membership} = Rooms.join_room(member.id, room.id)

    handler_id = "get-user-rooms-query-counter-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:chat, :repo, :query],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:query, metadata.query})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    rooms = Rooms.get_user_rooms(owner.id)
    member_counts = Enum.map(rooms, &length(&1.members))

    queries =
      Stream.repeatedly(fn ->
        receive do
          {:query, query} -> query
        after
          0 -> nil
        end
      end)
      |> Enum.take_while(& &1)
      |> Enum.filter(&(String.trim_leading(&1) |> String.starts_with?("SELECT")))

    assert member_counts == [2]

    # 2 SELECTs: (1) rooms + membership + creator + last-message preview via
    # lateral join; (2) one batched preload of members for all rooms. Keeping a
    # fixed count independent of the number of members is what prevents N+1.
    # The members are NOT joined into the main query anymore: joining them there
    # multiplied rows by member count and made the lateral subquery run once per
    # (room × member) row.
    assert length(queries) == 2
    assert Enum.all?(rooms, &Ecto.assoc_loaded?(&1.members))
  end

  test "get_user_rooms/1 keeps query count flat as members per room grow", %{
    owner: owner,
    member: member
  } do
    {:ok, room} = Rooms.create_room(%{"name" => "Flat Queries"}, owner.id)
    {:ok, _membership} = Rooms.join_room(member.id, room.id)

    for number <- 1..5 do
      {:ok, extra_member} = Identity.sync_user(%{"sub" => "flat-member-#{number}"}, %{})
      {:ok, _membership} = Rooms.join_room(extra_member.id, room.id)
    end

    handler_id = "get-user-rooms-flat-counter-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:chat, :repo, :query],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:query, metadata.query})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    [loaded_room] = Rooms.get_user_rooms(owner.id)

    queries =
      Stream.repeatedly(fn ->
        receive do
          {:query, query} -> query
        after
          0 -> nil
        end
      end)
      |> Enum.take_while(& &1)
      |> Enum.filter(&(String.trim_leading(&1) |> String.starts_with?("SELECT")))

    assert length(loaded_room.members) == 7
    assert length(queries) == 2
  end

  test "get_user_rooms/1 preloads creator", %{owner: owner, member: member} do
    {:ok, room} = Rooms.create_room(%{"name" => "Creator Preloaded"}, owner.id)
    {:ok, _membership} = Rooms.join_room(member.id, room.id)

    [loaded_room] = Rooms.get_user_rooms(owner.id)

    assert loaded_room.id == room.id
    assert Ecto.assoc_loaded?(loaded_room.creator)
    assert Ecto.assoc_loaded?(loaded_room.members)
  end

  test "list_available_rooms/2 limits explorer results without preloading unused associations", %{
    owner: owner,
    member: member
  } do
    search_prefix = "explorer-limit-#{System.unique_integer([:positive])}"

    for number <- 1..51 do
      assert {:ok, _room} =
               Rooms.create_room(
                 %{
                   "name" => "#{search_prefix}-#{String.pad_leading(to_string(number), 2, "0")}"
                 },
                 owner.id
               )
    end

    available_rooms = Rooms.list_available_rooms(member.id, search_prefix)

    assert length(available_rooms) == 50
    assert Enum.all?(available_rooms, &(not Ecto.assoc_loaded?(&1.creator)))
    assert Enum.all?(available_rooms, &(not Ecto.assoc_loaded?(&1.members)))
  end

  test "get_user_rooms/1 puts pinned rooms first with per-user pin metadata", %{
    owner: owner
  } do
    {:ok, regular_room} = Rooms.create_room(%{"name" => "Alpha"}, owner.id)
    {:ok, pinned_room} = Rooms.create_room(%{"name" => "Zulu"}, owner.id)
    assert {:ok, _membership} = Rooms.pin_room(owner.id, pinned_room.id)

    [first_room, second_room] = Rooms.get_user_rooms(owner.id)

    assert first_room.id == pinned_room.id
    assert %DateTime{} = first_room.pinned_at
    assert second_room.id == regular_room.id
    assert is_nil(second_room.pinned_at)
  end

  test "get_user_rooms/1 includes the latest message preview", %{owner: owner} do
    {:ok, room} = Rooms.create_room(%{"name" => "Com preview"}, owner.id)

    assert {:ok, _older} =
             Messages.create_message(%{"content" => "Mensagem antiga"}, owner.id, room.id)

    assert {:ok, _newer} =
             Messages.create_message(%{"content" => "Mensagem mais recente"}, owner.id, room.id)

    [room] = Rooms.get_user_rooms(owner.id)

    assert room.last_message_preview == "Mensagem mais recente"
  end

  test "fetch_member_room/2 uses a single query", %{owner: owner, member: member} do
    {:ok, room} = Rooms.create_room(%{"name" => "Single Query"}, owner.id)
    {:ok, _membership} = Rooms.join_room(member.id, room.id)

    handler_id = "fetch-member-room-query-counter-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:chat, :repo, :query],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:query, metadata.query})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {:ok, fetched_room} = Rooms.fetch_member_room(member.id, room.id)
    assert fetched_room.id == room.id

    queries =
      Stream.repeatedly(fn ->
        receive do
          {:query, query} -> query
        after
          0 -> nil
        end
      end)
      |> Enum.take_while(& &1)
      |> Enum.filter(&(String.trim_leading(&1) |> String.starts_with?("SELECT")))

    assert length(queries) == 1
  end

  test "room_members has a composite index on user_id and room_id" do
    %{rows: rows} =
      Repo.query!(
        "SELECT indexname FROM pg_indexes WHERE tablename = 'room_members' AND indexdef LIKE '%(user_id, room_id)%'"
      )

    assert rows != []
    assert Enum.any?(rows, fn [name] -> String.contains?(name, "user_id") end)
  end

  test "join_room is race-safe and idempotent", %{owner: owner, member: member} do
    {:ok, room} = Rooms.create_room(%{"name" => "Race Room"}, owner.id)

    tasks = for _ <- 1..10, do: Task.async(fn -> Rooms.join_room(member.id, room.id) end)
    results = Task.await_many(tasks)

    assert Enum.all?(results, fn
             {:ok, %RoomMember{user_id: user_id, room_id: room_id}} ->
               user_id == member.id and room_id == room.id

             _ ->
               false
           end)

    assert Enum.count(Rooms.get_room_members(room.id), &(&1.id == member.id)) == 1
  end

  test "room_member?/2 caches the result and avoids repeated queries", %{
    owner: owner,
    member: member
  } do
    {:ok, room} = Rooms.create_room(%{"name" => "Cache Test"}, owner.id)

    # Insert membership directly so the cache is not warmed by join_room.
    %RoomMember{}
    |> RoomMember.changeset(%{user_id: member.id, room_id: room.id})
    |> Repo.insert!()

    handler_id = "room-member-cache-counter-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:chat, :repo, :query],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:query, metadata.query})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert Rooms.room_member?(member.id, room.id)
    assert Rooms.room_member?(member.id, room.id)
    assert Rooms.room_member?(member.id, room.id)

    queries =
      Stream.repeatedly(fn ->
        receive do
          {:query, query} -> query
        after
          0 -> nil
        end
      end)
      |> Enum.take_while(& &1)
      |> Enum.filter(&(String.trim_leading(&1) |> String.starts_with?("SELECT")))

    assert length(queries) == 1
  end

  test "join_room/2 updates cache to true", %{owner: owner, member: member} do
    {:ok, room} = Rooms.create_room(%{"name" => "Cache Join"}, owner.id)

    refute Rooms.room_member?(member.id, room.id)
    assert {:ok, _} = Rooms.join_room(member.id, room.id)
    assert Rooms.room_member?(member.id, room.id)
  end

  test "leave_room/2 updates cache to false", %{owner: owner, member: member} do
    {:ok, room} = Rooms.create_room(%{"name" => "Cache Leave"}, owner.id)
    {:ok, _} = Rooms.join_room(member.id, room.id)

    assert Rooms.room_member?(member.id, room.id)
    assert {:ok, 1} = Rooms.leave_room(member.id, room.id)
    refute Rooms.room_member?(member.id, room.id)
  end
end
