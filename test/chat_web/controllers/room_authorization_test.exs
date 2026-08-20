defmodule ChatWeb.RoomAuthorizationTest do
  use ChatWeb.ConnCase, async: true

  alias Chat.Auth.Identity
  alias Chat.Messages
  alias Chat.Rooms
  alias ChatWeb.{MessageController, RoomController}

  setup do
    {:ok, owner} = Identity.sync_user(%{"sub" => "owner"}, %{})
    {:ok, outsider} = Identity.sync_user(%{"sub" => "outsider"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Privada"}, owner.id)

    %{owner: owner, outsider: outsider, room: room}
  end

  test "non-members cannot inspect a room", %{conn: conn, outsider: outsider, room: room} do
    conn = conn |> assign(:current_user, outsider) |> RoomController.show(%{"id" => room.id})

    assert %{"error" => "not_a_member"} = json_response(conn, 403)
  end

  test "non-members cannot inspect room presence", %{
    conn: conn,
    outsider: outsider,
    room: room
  } do
    conn =
      conn
      |> assign(:current_user, outsider)
      |> RoomController.online(%{"room_id" => room.id})

    assert %{"error" => "not_a_member"} = json_response(conn, 403)
  end

  test "message listing stops immediately for a non-member", %{
    conn: conn,
    outsider: outsider,
    room: room
  } do
    conn =
      conn
      |> assign(:current_user, outsider)
      |> MessageController.index(%{"room_id" => room.id})

    assert %{"error" => "not_a_member"} = json_response(conn, 403)
  end

  test "message listing rejects a malformed limit", %{conn: conn, owner: owner, room: room} do
    conn =
      conn
      |> assign(:current_user, owner)
      |> MessageController.index(%{"room_id" => room.id, "limit" => "invalid"})

    assert %{"error" => "invalid_limit"} = json_response(conn, 422)
  end

  test "message listing rejects limits outside the allowed range", %{owner: owner, room: room} do
    for limit <- ["0", "101"] do
      conn =
        build_conn()
        |> assign(:current_user, owner)
        |> MessageController.index(%{"room_id" => room.id, "limit" => limit})

      assert %{"error" => "invalid_limit"} = json_response(conn, 422)
    end
  end

  test "message listing rejects structured limit parameters", %{owner: owner, room: room} do
    for limit <- [["1"], %{"value" => "1"}] do
      conn =
        build_conn()
        |> assign(:current_user, owner)
        |> MessageController.index(%{"room_id" => room.id, "limit" => limit})

      assert %{"error" => "invalid_limit"} = json_response(conn, 422)
    end
  end

  test "message listing accepts pagination boundaries", %{owner: owner, room: room} do
    for limit <- ["1", "100"] do
      conn =
        build_conn()
        |> assign(:current_user, owner)
        |> MessageController.index(%{"room_id" => room.id, "limit" => limit})

      assert %{"messages" => []} = json_response(conn, 200)
    end
  end

  test "message listing accepts a valid UUID cursor", %{conn: conn, owner: owner, room: room} do
    conn =
      conn
      |> assign(:current_user, owner)
      |> MessageController.index(%{"room_id" => room.id, "before" => Ecto.UUID.generate()})

    assert %{"messages" => []} = json_response(conn, 200)
  end

  test "message listing rejects a malformed cursor", %{conn: conn, owner: owner, room: room} do
    conn =
      conn
      |> assign(:current_user, owner)
      |> MessageController.index(%{"room_id" => room.id, "before" => "invalid"})

    assert %{"error" => "invalid_before"} = json_response(conn, 422)
  end

  test "the creator cannot leave their room", %{conn: conn, owner: owner, room: room} do
    conn =
      conn
      |> assign(:current_user, owner)
      |> RoomController.leave(%{"room_id" => room.id})

    assert %{"error" => "creator_cannot_leave"} = json_response(conn, 409)
  end

  test "a non-member receives forbidden when leaving a room", %{
    conn: conn,
    outsider: outsider,
    room: room
  } do
    conn =
      conn
      |> assign(:current_user, outsider)
      |> RoomController.leave(%{"room_id" => room.id})

    assert %{"error" => "not_a_member"} = json_response(conn, 403)
  end

  test "a user can join using the router room_id parameter", %{
    conn: conn,
    outsider: outsider,
    room: room
  } do
    conn =
      conn
      |> assign(:current_user, outsider)
      |> RoomController.join(%{"room_id" => room.id})

    assert response(conn, 204)
    assert Rooms.room_member?(outsider.id, room.id)
  end

  test "a non-member cannot delete a message", %{
    conn: conn,
    owner: owner,
    outsider: outsider,
    room: room
  } do
    {:ok, message} = Messages.create_message(%{"content" => "segredo"}, owner.id, room.id)

    conn =
      conn
      |> assign(:current_user, outsider)
      |> MessageController.delete(%{"room_id" => room.id, "id" => message.id})

    assert %{"error" => "not_a_member"} = json_response(conn, 403)
  end

  test "an author cannot delete a message already read by another member", %{
    conn: conn,
    owner: owner,
    outsider: reader,
    room: room
  } do
    assert {:ok, _membership} = Rooms.join_room(reader.id, room.id)
    assert {:ok, message} = Messages.create_message(%{"content" => "lida"}, owner.id, room.id)
    assert :ok = Messages.mark_as_read(message.id, reader.id)

    conn =
      conn
      |> assign(:current_user, owner)
      |> MessageController.delete(%{"room_id" => room.id, "id" => message.id})

    assert %{"error" => "message_already_read"} = json_response(conn, 409)
    assert Messages.get_message(message.id)
  end

  test "message creation returns conflict when client_id is reused with different content", %{
    conn: conn,
    owner: owner,
    room: room
  } do
    client_id = Ecto.UUID.generate()

    first_conn =
      conn
      |> assign(:current_user, owner)
      |> MessageController.create(%{
        "room_id" => room.id,
        "message" => %{"content" => "Original", "client_id" => client_id}
      })

    assert %{"message" => %{"content" => "Original"}} = json_response(first_conn, 201)

    conflicting_conn =
      build_conn()
      |> assign(:current_user, owner)
      |> MessageController.create(%{
        "room_id" => room.id,
        "message" => %{"content" => "Diferente", "client_id" => client_id}
      })

    assert %{"error" => "client_id_conflict"} = json_response(conflicting_conn, 409)
    assert [%{content: "Original"}] = Messages.list_messages(room.id)
  end

  test "message creation rejects an invalid client_id", %{conn: conn, owner: owner, room: room} do
    conn =
      conn
      |> assign(:current_user, owner)
      |> MessageController.create(%{
        "room_id" => room.id,
        "message" => %{"content" => "Inválida", "client_id" => "not-a-uuid"}
      })

    assert %{"error" => "invalid_client_id"} = json_response(conn, 422)
    assert Messages.list_messages(room.id) == []
  end

  test "message creation rejects a non-map message payload", %{
    conn: conn,
    owner: owner,
    room: room
  } do
    conn =
      conn
      |> assign(:current_user, owner)
      |> MessageController.create(%{"room_id" => room.id, "message" => []})

    assert %{"error" => "invalid_message"} = json_response(conn, 422)
    assert Messages.list_messages(room.id) == []
  end
end
