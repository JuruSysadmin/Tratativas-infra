defmodule ChatWeb.OrderConversationControllerTest do
  use ChatWeb.ConnCase, async: false

  alias Chat.Auth.Identity
  alias Chat.Rooms
  alias Chat.Treatments

  setup do
    {:ok, user} = Identity.sync_user(%{"sub" => "order-conversation-user"}, %{})

    previous_module = Application.get_env(:chat, :authenticator_module)
    previous_pid = Application.get_env(:chat, :authenticator_spy_pid)
    previous_user = Application.get_env(:chat, :authenticator_spy_user)

    Application.put_env(:chat, :authenticator_module, Chat.AuthenticatorSpy)
    Application.put_env(:chat, :authenticator_spy_pid, self())
    Application.put_env(:chat, :authenticator_spy_user, user)

    on_exit(fn ->
      restore_env(:authenticator_module, previous_module)
      restore_env(:authenticator_spy_pid, previous_pid)
      restore_env(:authenticator_spy_user, previous_user)
    end)

    %{user: user}
  end

  test "lists only the authenticated user's order conversations", %{conn: conn, user: user} do
    {:ok, room} = Rooms.create_room(%{"name" => "Pedido 123", "order_id" => 123}, user.id)

    conn =
      conn
      |> put_req_header("authorization", "Bearer valid-token")
      |> get(~p"/api/order-conversations?order_ids=123,456")

    assert %{"conversations" => [%{"order_id" => 123, "room_id" => room_id}]} =
             json_response(conn, 200)

    assert room_id == room.id
  end

  test "creates an order conversation and its treatment audit event", %{conn: conn, user: user} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer valid-token")
      |> post(~p"/api/order-conversations", %{order_id: 789})

    assert %{
             "conversation" => %{
               "order_id" => 789,
               "room_id" => room_id,
               "treatment_protocol" => treatment_protocol
             }
           } =
             json_response(conn, 201)

    treatment = Chat.Repo.get_by!(Chat.Treatments.Treatment, room_id: room_id)
    assert treatment.order_id == 789
    assert treatment_protocol == Treatments.protocol(treatment)

    assert [%{event_type: "treatment_created", actor_id: actor_id}] =
             Treatments.list_audit_events(treatment.id, user.id)

    assert actor_id == user.id

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer valid-token")
      |> post(~p"/api/order-conversations", %{order_id: 789})

    assert %{"conversation" => %{"order_id" => 789, "room_id" => ^room_id}} =
             json_response(conn, 201)
  end

  test "rejects malformed order ids", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer valid-token")
      |> get(~p"/api/order-conversations?order_ids=123,invalid")

    assert %{"error" => "invalid_order_ids"} = json_response(conn, 400)
  end

  defp restore_env(key, nil), do: Application.delete_env(:chat, key)
  defp restore_env(key, value), do: Application.put_env(:chat, key, value)
end
