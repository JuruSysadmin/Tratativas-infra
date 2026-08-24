defmodule ChatWeb.OrderConversationControllerTest do
  use ChatWeb.ConnCase, async: false

  alias Chat.Auth.Identity
  alias Chat.Repo
  alias Chat.Rooms
  alias Chat.Treatments
  alias ChatWeb.OrderConversationController

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

  test "reports missing intake state with catalogued reasons", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer valid-token")
      |> get(~p"/api/treatment-intakes/791")

    assert %{
             "state" => "missing",
             "reasons" => [%{"code" => "delivery", "label" => "Entrega"} | _]
           } = json_response(conn, 200)
  end

  test "opens a structured treatment intake", %{conn: conn, user: user} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer valid-token")
      |> post(~p"/api/treatment-intakes", %{
        order_id: 792,
        reason_code: "billing",
        initial_description: "Nota fiscal ainda nao foi emitida."
      })

    assert %{
             "conversation" => %{
               "order_id" => 792,
               "room_id" => room_id,
               "treatment_protocol" => _treatment_protocol
             }
           } = json_response(conn, 201)

    treatment = Repo.get_by!(Chat.Treatments.Treatment, room_id: room_id)
    assert treatment.opened_by_id == user.id
    assert treatment.initial_description == "Nota fiscal ainda nao foi emitida."
  end

  test "requires structured intake before creating an order conversation", %{
    conn: conn,
    user: user
  } do
    conn =
      conn
      |> put_req_header("authorization", "Bearer valid-token")
      |> post(~p"/api/order-conversations", %{order_id: 789})

    assert %{"error" => "treatment_intake_required"} = json_response(conn, 409)

    assert {:ok, %{room: room, treatment: treatment}} =
             Treatments.open_structured_for_order(789, user.id, %{
               reason_code: "delivery",
               initial_description: "Pedido atrasado."
             })

    room_id = room.id

    assert %{"conversation" => %{"order_id" => 789, "room_id" => ^room_id}} =
             build_conn()
             |> put_req_header("authorization", "Bearer valid-token")
             |> post(~p"/api/order-conversations", %{order_id: 789})
             |> json_response(201)

    assert treatment.order_id == 789
  end

  test "rejects malformed order ids", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer valid-token")
      |> get(~p"/api/order-conversations?order_ids=123,invalid")

    assert %{"error" => "invalid_order_ids"} = json_response(conn, 400)
  end

  test "does not grant access while opening a closed order conversation", %{
    conn: conn,
    user: user
  } do
    {:ok, outsider} = Identity.sync_user(%{"sub" => "closed-order-controller-outsider"}, %{})
    {:ok, %{treatment: treatment, room: room}} = Treatments.open_for_order(790, user.id)
    {:ok, _closed} = Treatments.close(treatment, user.id)

    refute Rooms.room_member?(outsider.id, room.id)

    conn =
      conn
      |> assign(:current_user, outsider)
      |> OrderConversationController.create(%{"order_id" => 790})

    assert %{"error" => "order_conversation_forbidden"} = json_response(conn, 403)
    refute Rooms.room_member?(outsider.id, room.id)
    assert Repo.get!(Chat.Treatments.Treatment, treatment.id).status == "closed"
  end

  defp restore_env(key, nil), do: Application.delete_env(:chat, key)
  defp restore_env(key, value), do: Application.put_env(:chat, key, value)
end
