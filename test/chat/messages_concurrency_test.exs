defmodule Chat.MessagesConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Chat.Accounts.User
  alias Chat.Auth.Identity
  alias Chat.Messages
  alias Chat.Messages.{Message, RoomReadPosition}
  alias Chat.Repo
  alias Chat.Rooms
  alias Ecto.Adapters.SQL.Sandbox

  test "independent connections with the same client_id persist and broadcast once" do
    {user, room} = create_committed_room()
    client_id = Ecto.UUID.generate()
    attrs = %{"content" => "Envio concorrente real"}

    on_exit(fn -> delete_committed_user(user.id) end)
    Phoenix.PubSub.subscribe(Chat.PubSub, "room:#{room.id}")

    results =
      run_on_independent_connections([attrs, attrs], fn message_attrs ->
        Messages.create_message(message_attrs, user.id, room.id, client_id: client_id)
      end)

    assert [{:ok, first}, {:ok, second}] = results
    assert first.id == second.id

    assert unboxed(fn ->
             Repo.aggregate(
               from(message in Message, where: message.client_id == ^client_id),
               :count
             )
           end) == 1

    assert_receive {:message_created, published}
    assert published.id == first.id
    refute_receive {:message_created, _duplicate}
  end

  test "independent connections with different payloads return one explicit conflict" do
    {user, room} = create_committed_room()
    client_id = Ecto.UUID.generate()
    attrs = [%{"content" => "Concorrente A"}, %{"content" => "Concorrente B"}]

    on_exit(fn -> delete_committed_user(user.id) end)
    Phoenix.PubSub.subscribe(Chat.PubSub, "room:#{room.id}")

    results =
      run_on_independent_connections(attrs, fn message_attrs ->
        Messages.create_message(message_attrs, user.id, room.id, client_id: client_id)
      end)

    assert [{:ok, winner}] = Enum.filter(results, &match?({:ok, _message}, &1))

    assert [{:error, :client_id_conflict}] =
             Enum.filter(results, &match?({:error, :client_id_conflict}, &1))

    assert winner.content in ["Concorrente A", "Concorrente B"]

    assert unboxed(fn ->
             Repo.aggregate(
               from(message in Message, where: message.client_id == ^client_id),
               :count
             )
           end) == 1

    assert_receive {:message_created, published}
    assert published.id == winner.id
    refute_receive {:message_created, _duplicate}
  end

  test "independent connections never regress a room read position" do
    {author, room} = create_committed_room()

    {reader, older, newer} =
      unboxed(fn ->
        suffix = System.unique_integer([:positive])
        {:ok, reader} = Identity.sync_user(%{"sub" => "concurrency-reader-#{suffix}"}, %{})
        {:ok, _membership} = Rooms.join_room(reader.id, room.id)
        {:ok, first} = Messages.create_message(%{"content" => "Cursor A"}, author.id, room.id)
        {:ok, second} = Messages.create_message(%{"content" => "Cursor B"}, author.id, room.id)

        [older, newer] =
          Enum.sort_by(
            [first, second],
            &{NaiveDateTime.to_gregorian_seconds(&1.inserted_at), &1.id}
          )

        {reader, older, newer}
      end)

    on_exit(fn -> delete_committed_users([author.id, reader.id]) end)

    results =
      run_on_independent_connections([older.id, newer.id], fn message_id ->
        Messages.advance_room_read_position(reader.id, room.id, [message_id])
      end)

    assert Enum.all?(results, &match?({:ok, _position}, &1))

    position =
      unboxed(fn ->
        Repo.get_by!(RoomReadPosition, user_id: reader.id, room_id: room.id)
      end)

    assert position.last_read_message_id == newer.id
  end

  defp run_on_independent_connections(items, operation) do
    parent = self()

    tasks =
      Enum.map(items, &start_connection_task(&1, parent, operation))

    task_pids =
      Enum.map(tasks, fn _task ->
        assert_receive {:connection_ready, task_pid}
        task_pid
      end)

    assert MapSet.new(task_pids) == MapSet.new(tasks, & &1.pid)

    Enum.each(task_pids, &send(&1, :run_operation))
    Enum.map(tasks, &Task.await(&1, 5_000))
  end

  defp start_connection_task(item, parent, operation) do
    Task.async(fn ->
      unboxed(fn -> run_when_released(item, parent, operation) end)
    end)
  end

  defp run_when_released(item, parent, operation) do
    send(parent, {:connection_ready, self()})

    receive do
      :run_operation -> operation.(item)
    end
  end

  defp create_committed_room do
    suffix = System.unique_integer([:positive])

    unboxed(fn ->
      {:ok, user} =
        Identity.sync_user(%{"sub" => "concurrency-user-#{suffix}"}, %{
          "username" => "concurrency-user-#{suffix}"
        })

      {:ok, room} = Rooms.create_room(%{"name" => "Concorrência #{suffix}"}, user.id)
      {user, room}
    end)
  end

  defp delete_committed_user(user_id) do
    unboxed(fn -> Repo.delete_all(from(user in User, where: user.id == ^user_id)) end)
  end

  defp delete_committed_users(user_ids) do
    unboxed(fn -> Repo.delete_all(from(user in User, where: user.id in ^user_ids)) end)
  end

  defp unboxed(fun), do: Sandbox.unboxed_run(Repo, fun)
end
