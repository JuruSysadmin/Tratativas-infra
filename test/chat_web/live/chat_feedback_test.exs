defmodule ChatWeb.ChatFeedbackTest do
  use Chat.DataCase, async: false

  import Phoenix.Component, only: [assign: 2]

  alias Chat.Auth.Identity
  alias Chat.Messages
  alias Chat.Repo
  alias Chat.Rooms
  alias ChatWeb.ChatLive
  alias ChatWeb.ChatMessages
  alias ChatWeb.Presence
  alias Phoenix.LiveView.Utils

  setup do
    {:ok, user} = Identity.sync_user(%{"sub" => "feedback-user"}, %{})
    {:ok, other} = Identity.sync_user(%{"sub" => "feedback-other"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Feedback"}, user.id)
    {:ok, second_room} = Rooms.create_room(%{"name" => "Outra thread"}, user.id)
    {:ok, _membership} = Rooms.join_room(other.id, room.id)

    socket =
      %Phoenix.LiveView.Socket{
        private: %{lifecycle: %Phoenix.LiveView.Lifecycle{}, live_temp: %{}}
      }
      |> assign(%{
        current_user: user,
        current_room: room,
        rooms: [room, second_room],
        message_ids: MapSet.new(),
        message_map: %{},
        message_statuses: %{},
        oldest_message_id: nil,
        pending_messages: %{},
        unread_counts: %{},
        mention_unread_count: 0,
        mention_suggestions: [],
        status_messages: [],
        pending_presence_leaves: %{},
        online_users: [],
        typing_users: [],
        input_text: ""
      })
      |> Phoenix.LiveView.stream(:messages, [])

    %{other: other, room: room, second_room: second_room, socket: socket, user: user}
  end

  test "queues a message as sending and marks a validation failure for retry", %{
    room: room,
    socket: socket
  } do
    content = String.duplicate("x", 4_001)
    socket = %{socket | private: Map.put(socket.private, :live_temp, %{})}

    assert {:noreply, socket} =
             ChatLive.handle_event("send_message", %{"text" => content}, socket)

    assert [{_pending_id, %{status: :sending} = pending}] =
             Map.to_list(socket.assigns.pending_messages)

    assert ["scroll_to_bottom", %{}] in Utils.get_push_events(socket)

    assert_receive {:persist_message, pending_id, ^content, room_id}
    assert pending_id == pending.id
    assert room_id == room.id
    client_id = pending.client_id
    assert {:ok, ^client_id} = Ecto.UUID.cast(client_id)
    refute MapSet.member?(socket.assigns.message_ids, pending_id)
    refute Map.has_key?(socket.assigns.message_map, pending_id)

    assert {:noreply, socket} =
             ChatLive.handle_info({:persist_message, pending.id, content, room.id}, socket)

    assert %{status: :failed} = socket.assigns.pending_messages[pending.id]

    assert {:noreply, socket} =
             ChatLive.handle_event("retry_message", %{"message_id" => pending.id}, socket)

    assert %{status: :sending} = socket.assigns.pending_messages[pending.id]
    assert_receive {:persist_message, _, ^content, ^room_id}
  end

  test "wires the send scroll event in the browser asset" do
    javascript = File.read!(Path.expand("../../../assets/js/app.js", __DIR__))

    assert javascript =~ ~s(window.addEventListener("phx:scroll_to_bottom")
    assert javascript =~ "messages.scrollTop = messages.scrollHeight"
  end

  test "successful persistence replaces and clears the optimistic message", %{
    socket: socket
  } do
    content = "Mensagem confirmada"

    assert {:noreply, socket} =
             ChatLive.handle_event("send_message", %{"text" => content}, socket)

    assert_receive {:persist_message, pending_id, ^content, room_id}

    assert {:noreply, socket} =
             ChatLive.handle_info({:persist_message, pending_id, content, room_id}, socket)

    assert socket.assigns.pending_messages == %{}
    refute MapSet.member?(socket.assigns.message_ids, pending_id)

    assert Enum.any?(socket.assigns.message_map, fn {_id, message} ->
             message.content == content && message.client_id != nil
           end)
  end

  test "ignores optimistic message ids when marking messages as read", %{socket: socket} do
    assert {:noreply, returned_socket} =
             ChatLive.handle_event(
               "mark_read",
               %{"message_ids" => ["pending-#{Ecto.UUID.generate()}"]},
               socket
             )

    assert returned_socket == socket
  end

  test "marking multiple messages as read emits one grouped event", %{
    other: author,
    room: room,
    socket: socket
  } do
    {:ok, first} =
      Messages.create_message(%{"content" => "Primeira leitura"}, author.id, room.id)

    {:ok, second} =
      Messages.create_message(%{"content" => "Segunda leitura"}, author.id, room.id)

    Phoenix.PubSub.subscribe(Chat.PubSub, "room:#{room.id}")

    assert {:noreply, returned_socket} =
             ChatLive.handle_event(
               "mark_read",
               %{"message_ids" => [first.id, second.id]},
               socket
             )

    assert returned_socket.assigns.mention_notifications == []
    assert returned_socket.assigns.mention_unread_count == 0

    expected_ids = [first.id, second.id]
    user_id = socket.assigns.current_user.id

    assert_receive {:read_receipts_updated, room_id, ^user_id, inserted_ids}
    assert room_id == room.id
    assert Enum.sort(inserted_ids) == Enum.sort(expected_ids)
    refute_receive {:read_receipt_updated, _, _, _}
  end

  test "marking a visible message persists the room position and clears its badge", %{
    other: author,
    room: room,
    socket: socket,
    user: reader
  } do
    assert {:ok, message} =
             Messages.create_message(%{"content" => "Visível e persistente"}, author.id, room.id)

    socket = assign(socket, %{unread_counts: %{room.id => 1}})

    assert {:noreply, socket} =
             ChatLive.handle_event("mark_read", %{"message_ids" => [message.id]}, socket)

    assert Map.get(socket.assigns.unread_counts, room.id, 0) == 0
    assert Messages.unread_counts_by_room(reader.id, [room.id]) == %{}
  end

  test "marking an old visible message preserves unread messages after the cursor", %{
    other: author,
    room: room,
    socket: socket,
    user: reader
  } do
    assert {:ok, old_message} =
             Messages.create_message(
               %{"content" => "Mensagem antiga visível"},
               author.id,
               room.id
             )

    for index <- 1..3 do
      assert {:ok, _message} =
               Messages.create_message(%{"content" => "Posterior #{index}"}, author.id, room.id)
    end

    assert {:ok, _position} =
             Messages.advance_room_read_position(reader.id, room.id, [old_message.id])

    socket = assign(socket, %{unread_counts: %{room.id => 3}})

    assert {:noreply, socket} =
             ChatLive.handle_event("mark_read", %{"message_ids" => [old_message.id]}, socket)

    assert socket.assigns.unread_counts[room.id] == 3
  end

  test "marking read does not persist receipts after membership revocation", %{
    other: author,
    room: room,
    socket: socket,
    user: reader
  } do
    assert {:ok, message} =
             Messages.create_message(%{"content" => "Não deve ser lida"}, author.id, room.id)

    membership = Repo.get_by!(Chat.Rooms.RoomMember, user_id: reader.id, room_id: room.id)
    Repo.delete!(membership)

    assert {[], false} = ChatMessages.mark_read(socket, [message.id])
    assert Messages.list_readers(message.id) == []

    assert Repo.get_by(Chat.Messages.RoomReadPosition, user_id: reader.id, room_id: room.id) ==
             nil
  end

  test "a read receipt event synchronizes the same user's badge on another session", %{
    other: author,
    room: room,
    socket: socket,
    user: reader
  } do
    assert {:ok, message} =
             Messages.create_message(
               %{"content" => "Lida por @feedback-user em outro dispositivo"},
               author.id,
               room.id
             )

    other_session =
      assign(socket, %{
        current_room: nil,
        mention_unread_count: 1,
        unread_counts: %{room.id => 1}
      })

    Phoenix.PubSub.subscribe(Chat.PubSub, "room:#{room.id}")

    assert {:noreply, _reading_session} =
             ChatLive.handle_event("mark_read", %{"message_ids" => [message.id]}, socket)

    assert_receive event = {:read_receipts_updated, room_id, reader_id, [message_id]}
    assert room_id == room.id
    assert reader_id == reader.id
    assert message_id == message.id

    assert {:noreply, other_session} = ChatLive.handle_info(event, other_session)
    assert Map.get(other_session.assigns.unread_counts, room.id, 0) == 0
    assert other_session.assigns.mention_unread_count == 0
  end

  test "grouped read receipt broadcasts reload database counts idempotently", %{
    other: other,
    room: room,
    socket: socket,
    user: user
  } do
    {:ok, first} =
      Messages.create_message(%{"content" => "Primeira idempotente"}, user.id, room.id)

    {:ok, second} =
      Messages.create_message(%{"content" => "Segunda idempotente"}, user.id, room.id)

    assert :ok = Messages.mark_as_read(first.id, other.id)
    assert :ok = Messages.mark_as_read(second.id, other.id)

    socket =
      assign(socket, %{
        message_ids: MapSet.new([first.id, second.id]),
        message_order: [first.id, second.id],
        message_map: %{first.id => first, second.id => second},
        message_statuses: %{first.id => :sent, second.id => :sent}
      })

    handler_id = "grouped-read-receipts-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:chat, :repo, :query],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:grouped_read_receipts_query, metadata.query})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    event = {:read_receipts_updated, room.id, other.id, [first.id, second.id]}
    assert {:noreply, socket} = ChatLive.handle_info(event, socket)

    receipt_queries =
      Stream.repeatedly(fn ->
        receive do
          {:grouped_read_receipts_query, query} -> query
        after
          0 -> nil
        end
      end)
      |> Enum.take_while(& &1)
      |> Enum.filter(&String.contains?(&1, ~s(FROM "read_receipts")))

    assert length(receipt_queries) == 1

    assert {:noreply, socket} = ChatLive.handle_info(event, socket)

    assert socket.assigns.message_map[first.id].read_count == 1
    assert socket.assigns.message_map[second.id].read_count == 1
  end

  test "increments unread messages outside the selected room and clears on selection", %{
    other: author,
    second_room: second_room,
    socket: socket,
    user: reader
  } do
    assert {:ok, _membership} = Rooms.join_room(author.id, second_room.id)

    {:ok, message} =
      Messages.create_message(%{"content" => "Não lida"}, author.id, second_room.id)

    assert {:noreply, socket} = ChatLive.handle_info({:message_created, message}, socket)
    assert socket.assigns.unread_counts[second_room.id] == 1
    assert Messages.unread_counts_by_room(reader.id, [second_room.id]) == %{second_room.id => 1}
    assert MapSet.size(socket.assigns.message_ids) == 0

    assert {:noreply, socket} =
             ChatLive.handle_event("select_room", %{"room_id" => second_room.id}, socket)

    assert Map.get(socket.assigns.unread_counts, second_room.id, 0) == 0
    assert Messages.unread_counts_by_room(reader.id, [second_room.id]) == %{}
  end

  test "does not count the current user's message as unread", %{
    second_room: second_room,
    socket: socket,
    user: user
  } do
    assert {:ok, message} =
             Messages.create_message(
               %{"content" => "Enviada em outra sessão"},
               user.id,
               second_room.id
             )

    assert {:noreply, socket} = ChatLive.handle_info({:message_created, message}, socket)

    assert socket.assigns.unread_counts == %{}
    assert Messages.unread_counts_by_room(user.id, [second_room.id]) == %{}
  end

  test "deleting an unread message refreshes the badge outside the selected room", %{
    other: author,
    second_room: second_room,
    socket: socket
  } do
    assert {:ok, _membership} = Rooms.join_room(author.id, second_room.id)

    assert {:ok, message} =
             Messages.create_message(%{"content" => "Será removida"}, author.id, second_room.id)

    socket = assign(socket, %{unread_counts: %{second_room.id => 1}})
    assert {:ok, _deleted} = Messages.delete_message(message)

    assert {:noreply, socket} =
             ChatLive.handle_info({:message_deleted, second_room.id, message.id}, socket)

    assert Map.get(socket.assigns.unread_counts, second_room.id, 0) == 0
  end

  test "initialization restores persisted unread counts", %{
    other: author,
    room: room,
    socket: socket
  } do
    assert {:ok, _message} =
             Messages.create_message(
               %{"content" => "Persistida antes do mount"},
               author.id,
               room.id
             )

    initialized_socket = ChatWeb.RoomNavigation.init(socket)

    assert initialized_socket.assigns.unread_counts == %{room.id => 1}
  end

  test "room selection broadcasts mention state only after its transaction commits", %{
    second_room: second_room,
    socket: socket,
    user: user
  } do
    assert {:ok, _message} =
             Messages.create_message(
               %{"content" => "Confirma antes de publicar"},
               user.id,
               second_room.id
             )

    loaded_room = Repo.preload(second_room, [:creator, :members])
    socket = assign(socket, %{rooms: [loaded_room]})
    handler_id = "chat-room-commit-order-#{System.unique_integer([:positive])}"
    test_pid = self()

    Phoenix.PubSub.subscribe(Chat.PubSub, "user:#{user.id}")

    :ok =
      :telemetry.attach(
        handler_id,
        [:chat, :repo, :query],
        fn _event, _measurements, metadata, _config ->
          normalized_query = metadata.query |> String.trim() |> String.downcase()

          if normalized_query == "commit" or
               String.starts_with?(normalized_query, "release savepoint") do
            send(test_pid, :room_selection_committed)
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {:noreply, _selected_socket} =
             ChatLive.handle_event("select_room", %{"room_id" => loaded_room.id}, socket)

    first_event =
      receive do
        :room_selection_committed -> :committed
        {:mention_state_changed, _payload} -> :broadcast
      end

    assert first_event == :committed
    assert_receive {:mention_state_changed, %{room_id: room_id}}
    assert room_id == loaded_room.id
  end

  test "selecting an already loaded room queries its page, read metadata and mention badge", %{
    second_room: second_room,
    socket: socket
  } do
    loaded_room = Repo.preload(second_room, [:creator, :members])
    socket = assign(socket, %{rooms: [loaded_room]})
    handler_id = "chat-room-selection-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:chat, :repo, :query],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:room_selection_query, metadata.query})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {:noreply, selected_socket} =
             ChatLive.handle_event("select_room", %{"room_id" => loaded_room.id}, socket)

    assert selected_socket.assigns.current_room.id == loaded_room.id

    select_queries =
      Stream.repeatedly(fn ->
        receive do
          {:room_selection_query, query} -> query
        after
          0 -> nil
        end
      end)
      |> Enum.take_while(& &1)
      |> Enum.filter(&(String.trim_leading(&1) |> String.starts_with?("SELECT")))

    assert length(select_queries) == 14
    assert Enum.count(select_queries, &String.contains?(&1, ~s(FROM "messages"))) == 4
    assert Enum.count(select_queries, &String.contains?(&1, ~s(FROM "read_receipts"))) == 1

    assert Enum.count(select_queries, &String.contains?(&1, ~s(FROM "room_delivery_positions"))) ==
             1

    assert Enum.count(select_queries, &String.contains?(&1, ~s(FROM "message_mentions"))) == 3
  end

  test "presence changes create human status notices", %{
    other: other,
    room: room,
    socket: socket
  } do
    topic = "room:#{room.id}"

    {:ok, _ref} =
      Presence.track(self(), topic, to_string(other.id), %{
        id: other.id,
        username: other.username
      })

    on_exit(fn -> Presence.untrack(self(), topic, to_string(other.id)) end)

    broadcast = %Phoenix.Socket.Broadcast{topic: topic, event: "presence_diff", payload: %{}}
    assert {:noreply, socket} = ChatLive.handle_info(broadcast, socket)

    assert [%{kind: :joined, username: username}] = socket.assigns.status_messages
    assert username == other.username
  end

  test "presence updates delivery counts without changing message order", %{
    other: other,
    room: room,
    socket: socket,
    user: user
  } do
    messages =
      for index <- 1..3 do
        {:ok, message} =
          Messages.create_message(%{"content" => "Ordem presence #{index}"}, user.id, room.id)

        message
      end

    socket = ChatLive.handle_event("select_room", %{"room_id" => room.id}, socket) |> elem(1)
    expected_order = Enum.map(messages, & &1.id)
    assert socket.assigns.message_order == expected_order

    {:ok, _ref} =
      Presence.track(self(), "room:#{room.id}", to_string(other.id), %{
        id: other.id,
        username: other.username
      })

    on_exit(fn -> Presence.untrack(self(), "room:#{room.id}", to_string(other.id)) end)

    broadcast = %Phoenix.Socket.Broadcast{
      topic: "room:#{room.id}",
      event: "presence_diff",
      payload: %{}
    }

    assert {:noreply, socket} = ChatLive.handle_info(broadcast, socket)
    assert socket.assigns.message_order == expected_order
  end

  test "a quick F5 is treated as reconnection instead of leave and rejoin", %{
    other: other,
    room: room,
    socket: socket
  } do
    topic = "room:#{room.id}"
    meta = %{id: other.id, username: other.username}
    broadcast = %Phoenix.Socket.Broadcast{topic: topic, event: "presence_diff", payload: %{}}

    {:ok, _ref} = Presence.track(self(), topic, to_string(other.id), meta)
    assert {:noreply, socket} = ChatLive.handle_info(broadcast, socket)
    socket = assign(socket, %{status_messages: []})

    :ok = Presence.untrack(self(), topic, to_string(other.id))
    assert {:noreply, socket} = ChatLive.handle_info(broadcast, socket)
    assert socket.assigns.status_messages == []
    assert Map.has_key?(socket.assigns.pending_presence_leaves, other.id)

    {:ok, _ref} = Presence.track(self(), topic, to_string(other.id), meta)
    assert {:noreply, socket} = ChatLive.handle_info(broadcast, socket)
    assert socket.assigns.status_messages == []
    refute Map.has_key?(socket.assigns.pending_presence_leaves, other.id)

    :ok = Presence.untrack(self(), topic, to_string(other.id))
    assert {:noreply, socket} = ChatLive.handle_info(broadcast, socket)

    timer_token =
      socket.assigns.pending_presence_leaves |> Map.fetch!(other.id) |> Map.fetch!(:token)

    assert {:noreply, socket} =
             ChatLive.handle_info(
               {:confirm_presence_leave, room.id, other.id, timer_token},
               socket
             )

    assert [%{kind: :left, username: username}] = socket.assigns.status_messages
    assert username == other.username
  end

  test "keeps a confirmed leave when another user joins at the same time", %{
    other: leaving_user,
    room: room,
    socket: socket
  } do
    {:ok, joining_user} = Identity.sync_user(%{"sub" => "feedback-joining"}, %{})
    {:ok, _membership} = Rooms.join_room(joining_user.id, room.id)

    topic = "room:#{room.id}"
    broadcast = %Phoenix.Socket.Broadcast{topic: topic, event: "presence_diff", payload: %{}}

    {:ok, _ref} =
      Presence.track(self(), topic, to_string(leaving_user.id), %{
        id: leaving_user.id,
        username: leaving_user.username
      })

    on_exit(fn ->
      Presence.untrack(self(), topic, to_string(leaving_user.id))
      Presence.untrack(self(), topic, to_string(joining_user.id))
    end)

    assert {:noreply, socket} = ChatLive.handle_info(broadcast, socket)
    socket = assign(socket, %{status_messages: []})

    :ok = Presence.untrack(self(), topic, to_string(leaving_user.id))
    assert {:noreply, socket} = ChatLive.handle_info(broadcast, socket)

    timer_token =
      socket.assigns.pending_presence_leaves
      |> Map.fetch!(leaving_user.id)
      |> Map.fetch!(:token)

    assert {:noreply, socket} =
             ChatLive.handle_info(
               {:confirm_presence_leave, room.id, leaving_user.id, timer_token},
               socket
             )

    {:ok, _ref} =
      Presence.track(self(), topic, to_string(joining_user.id), %{
        id: joining_user.id,
        username: joining_user.username
      })

    assert {:noreply, socket} = ChatLive.handle_info(broadcast, socket)

    statuses = socket.assigns.status_messages
    assert length(statuses) == 2
    assert Enum.any?(statuses, &(&1.kind == :left and &1.username == leaving_user.username))
    assert Enum.any?(statuses, &(&1.kind == :joined and &1.username == joining_user.username))
  end

  test "template exposes delivery, unread and connection feedback" do
    message_template =
      File.read!(
        Path.expand("../../../lib/chat_web/live/components/message_components.ex", __DIR__)
      )

    sidebar_template =
      File.read!(
        Path.expand("../../../lib/chat_web/live/components/room_sidebar_component.ex", __DIR__)
      )

    layout = File.read!(Path.expand("../../../lib/chat_web/live/chat_live.html.heex", __DIR__))

    assert message_template =~ "message-delivery-status"
    assert message_template =~ ~s(phx-click="retry_message")
    assert sidebar_template =~ "room-unread-count"
    assert layout =~ "connection-status"
    assert message_template =~ ~s(role="status")
  end
end
