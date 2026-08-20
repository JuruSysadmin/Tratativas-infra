defmodule ChatWeb.ChatLiveStreamTest do
  use ChatWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Chat.Auth.Identity
  alias Chat.Messages
  alias Chat.Repo
  alias Chat.Rooms
  alias Phoenix.HTML.Safe

  setup %{conn: conn} do
    {:ok, user} = Identity.sync_user(%{"sub" => "stream-user"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Sala em stream"}, user.id)
    conn = init_test_session(conn, %{"user_id" => user.id})

    %{conn: conn, room: room, user: user}
  end

  test "renders messages in a LiveView stream with viewport pagination", %{
    conn: conn,
    room: room,
    user: user
  } do
    {:ok, message} =
      Messages.create_message(%{"content" => "Mensagem no stream"}, user.id, room.id)

    {:ok, view, _html} = live(conn, ~p"/chat?room_id=#{room.id}")

    assert has_element?(
             view,
             "#messages-list[phx-update=stream][phx-viewport-top=load_older_messages]"
           )

    assert has_element?(view, "#messages-list > #messages-#{message.id}", "Mensagem no stream")
    assert has_element?(view, "#messages-loading[role=status][aria-live=polite]")
    assert has_element?(view, "#messages-loading[data-initial-loading]", "Carregando mensagens…")
    assert has_element?(view, ~s(#chat-page[phx-hook="NotificationSound"]))
    assert has_element?(view, ~s(#connection-status[phx-hook="ConnectionStatus"]))
    assert has_element?(view, "#connection-status[data-connection-state='connected']")
  end

  test "renders one message when it receives a duplicate message_created event", %{
    conn: conn,
    room: room,
    user: user
  } do
    {:ok, message} =
      Messages.create_message(%{"content" => "Evento duplicado"}, user.id, room.id)

    {:ok, view, _html} = live(conn, ~p"/chat?room_id=#{room.id}")

    send(view.pid, {:message_created, message})
    send(view.pid, {:message_created, message})

    html = view |> element("#messages-list") |> render()

    assert [_, _] = String.split(html, "Evento duplicado")
  end

  test "pending message area tolerates order entries missing from map", %{
    room: room,
    user: user
  } do
    pending_id = "pending-#{Ecto.UUID.generate()}"
    room = Repo.preload(room, [:creator, :members])

    assigns = %{
      current_room: room,
      current_user: user,
      messages: [],
      has_more_messages: false,
      pending_messages: %{},
      pending_message_order: [pending_id],
      status_messages: [],
      typing_users: [],
      input_text: "",
      mention_suggestions: [],
      message_statuses: %{},
      rooms: [room]
    }

    html =
      ChatWeb.ChatAreaComponent.chat_area(assigns)
      |> Safe.to_iodata()
      |> to_string()

    assert html =~ "pending-messages"
    refute html =~ "data-pending-message"
  end

  test "prepends older messages without removing the current page", %{
    conn: conn,
    room: room,
    user: user
  } do
    messages =
      for index <- 1..51 do
        {:ok, message} =
          Messages.create_message(%{"content" => "Histórico #{index}"}, user.id, room.id)

        message
      end

    latest = Messages.list_messages(room.id, limit: 50)
    latest_ids = MapSet.new(latest, & &1.id)
    oldest = Enum.find(messages, &(not MapSet.member?(latest_ids, &1.id)))
    newest = List.last(latest)
    {:ok, view, _html} = live(conn, ~p"/chat?room_id=#{room.id}")

    refute has_element?(view, "#messages-#{oldest.id}")
    assert has_element?(view, "#messages-#{newest.id}")

    view
    |> element("#messages-list")
    |> render_hook("load_older_messages")

    assert has_element?(view, "#messages-#{oldest.id}")
    assert has_element?(view, "#messages-#{newest.id}")
  end

  test "keeps consecutive sends visible and ordered after refresh", %{
    conn: conn,
    room: room,
    user: user
  } do
    {:ok, view, _html} = live(conn, ~p"/chat?room_id=#{room.id}")
    contents = ["Primeira rápida", "Segunda rápida", "Terceira rápida"]

    Enum.each(contents, fn content ->
      view
      |> form("#message-form", %{"text" => content})
      |> render_submit()
    end)

    assert eventually(fn -> messages_rendered_in_order?(view, contents) end)
    assert Enum.map(Messages.list_messages(room.id), & &1.content) == contents
    GenServer.stop(view.pid)

    refreshed_conn =
      Phoenix.ConnTest.build_conn()
      |> init_test_session(%{"user_id" => user.id})

    {:ok, refreshed_view, _html} = live(refreshed_conn, ~p"/chat?room_id=#{room.id}")
    positions = message_positions(refreshed_view, contents)
    assert Enum.all?(positions, &is_integer/1)
    assert positions == Enum.sort(positions)
  end

  test "renders failed optimistic messages outside the persisted stream", %{
    conn: conn,
    room: room
  } do
    {:ok, view, _html} = live(conn, ~p"/chat?room_id=#{room.id}")

    view
    |> form("#message-form", %{"text" => String.duplicate("x", 4_001)})
    |> render_submit()

    assert eventually(fn -> has_element?(view, "#pending-messages [data-pending-message]") end)
    refute has_element?(view, "#messages-list [data-pending-message]")
    assert has_element?(view, "#pending-messages", "Falha no envio")
  end

  test "replays a durable outbox message with its client id after reconnect", %{
    conn: conn,
    room: room
  } do
    client_id = Ecto.UUID.generate()
    content = "Mensagem enviada durante offline"
    {:ok, view, _html} = live(conn, ~p"/chat?room_id=#{room.id}")

    render_hook(view, "restore_pending_messages", %{
      "messages" => [%{"client_id" => client_id, "content" => content}]
    })

    assert eventually(fn ->
             [%{client_id: ^client_id, content: ^content}] = Messages.list_messages(room.id)
           end)

    assert has_element?(view, "#messages-list", content)
    refute has_element?(view, "#pending-messages [data-pending-message]")
  end

  test "persists a browser outbox message with its client id", %{conn: conn, room: room} do
    client_id = Ecto.UUID.generate()
    content = "Mensagem da outbox do navegador"
    {:ok, view, _html} = live(conn, ~p"/chat?room_id=#{room.id}")

    render_submit(view, "send_message", %{"client_id" => client_id, "text" => content})

    assert eventually(fn ->
             [%{client_id: ^client_id, content: ^content}] = Messages.list_messages(room.id)
           end)
  end

  test "preserves pending messages when the LiveView reconnects", %{
    conn: conn,
    room: room,
    user: user
  } do
    pending_content = String.duplicate("x", 4_001)
    {:ok, view, _html} = live(conn, ~p"/chat?room_id=#{room.id}")

    view
    |> form("#message-form", %{"text" => pending_content})
    |> render_submit()

    assert eventually(fn -> has_element?(view, "#pending-messages [data-pending-message]") end)
    GenServer.stop(view.pid)

    refreshed_conn =
      Phoenix.ConnTest.build_conn()
      |> init_test_session(%{"user_id" => user.id})

    {:ok, refreshed_view, _html} = live(refreshed_conn, ~p"/chat?room_id=#{room.id}")

    render_hook(refreshed_view, "restore_pending_messages", %{
      "messages" => [
        %{
          "client_id" => Ecto.UUID.generate(),
          "content" => pending_content
        }
      ]
    })

    assert has_element?(refreshed_view, "#pending-messages", pending_content)
  end

  test "pending message hook persists and restores browser state" do
    hook = File.read!(Path.expand("../../../assets/js/hooks/pending_messages.js", __DIR__))

    assert hook =~ "window.localStorage"
    assert hook =~ "restore_pending_messages"
    assert hook =~ "data-pending-message"
  end

  test "loads read receipt metadata in one query per LiveView mount", %{
    conn: conn,
    room: room,
    user: user
  } do
    for index <- 1..3 do
      {:ok, _message} =
        Messages.create_message(%{"content" => "Tooltip em lote #{index}"}, user.id, room.id)
    end

    handler_id = "read-metadata-query-count-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:chat, :repo, :query],
        fn _event, _measurements, metadata, _config ->
          if String.contains?(metadata.query, ~s(FROM "read_receipts")) do
            send(test_pid, {:read_receipt_query, metadata.query})
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    {:ok, view, _html} = live(conn, ~p"/chat?room_id=#{room.id}")
    _ = render(view)

    queries = drain_read_receipt_queries([])
    # live/2 performs one disconnected render and one connected mount.
    assert length(queries) <= 2, inspect(queries)
  end

  defp messages_rendered_in_order?(view, contents) do
    positions = message_positions(view, contents)
    Enum.all?(positions, &is_integer/1) && positions == Enum.sort(positions)
  end

  defp message_positions(view, contents) do
    html = view |> element("#messages-list") |> render()

    Enum.map(contents, fn content ->
      case :binary.match(html, content) do
        {position, _length} -> position
        :nomatch -> nil
      end
    end)
  end

  defp eventually(assertion, attempts \\ 20)

  defp eventually(assertion, attempts) when attempts > 0 do
    if assertion.(), do: true, else: eventually(assertion, attempts - 1)
  end

  defp eventually(_assertion, 0), do: false

  defp drain_read_receipt_queries(queries) do
    receive do
      {:read_receipt_query, query} -> drain_read_receipt_queries([query | queries])
    after
      0 -> Enum.reverse(queries)
    end
  end
end
