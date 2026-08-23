defmodule ChatWeb.TreatmentQueueControllerTest do
  use ChatWeb.ConnCase, async: true

  alias Chat.Accounts.User
  alias Chat.Auth.Identity
  alias Chat.Repo
  alias Chat.Rooms
  alias Chat.Treatments
  alias ChatWeb.TreatmentQueueController

  setup do
    {:ok, owner} = Identity.sync_user(%{"sub" => "owner-commercial"}, %{})
    agent = logistics_agent_fixture("agent-queue")

    assert {:ok, %{treatment: treatment_1, room: room_1}} =
             Treatments.open_for_order(9_998_044_301, owner.id)

    assert {:ok, %{treatment: treatment_2, room: room_2}} =
             Treatments.open_for_order(9_998_044_302, owner.id)

    assert {:ok, _} = Rooms.join_room(agent.id, room_1.id)
    assert {:ok, _} = Rooms.join_room(agent.id, room_2.id)

    %{
      owner: owner,
      agent: agent,
      treatment_1: treatment_1,
      treatment_2: treatment_2,
      room_1: room_1,
      room_2: room_2
    }
  end

  test "returns 200 with queue items and pagination metadata", %{
    conn: conn,
    agent: agent,
    room_1: room_1,
    room_2: room_2
  } do
    conn =
      conn
      |> assign(:current_user, agent)
      |> TreatmentQueueController.index(%{})

    assert %{
             "items" => items,
             "pagination" => %{
               "has_more" => false,
               "next_cursor" => nil,
               "limit" => 50
             }
           } = json_response(conn, 200)

    assert length(items) >= 2

    room_ids = Enum.map(items, & &1["room_id"])
    assert room_1.id in room_ids
    assert room_2.id in room_ids

    first_item = List.first(items)
    assert Map.has_key?(first_item, "order_id")
    assert Map.has_key?(first_item, "room_id")
    assert Map.has_key?(first_item, "protocol")
    assert Map.has_key?(first_item, "status")
    assert Map.has_key?(first_item, "assigned_agent_id")
    assert Map.has_key?(first_item, "assigned_agent_name")
  end

  test "paginates results with custom limit and keyset cursor", %{
    conn: conn,
    agent: agent
  } do
    # Page 1 (limit 1)
    conn_page_1 =
      conn
      |> assign(:current_user, agent)
      |> TreatmentQueueController.index(%{"limit" => "1"})

    assert %{
             "items" => [page_1_item],
             "pagination" => %{
               "has_more" => true,
               "next_cursor" => next_cursor,
               "limit" => 1
             }
           } = json_response(conn_page_1, 200)

    assert is_binary(next_cursor) and next_cursor != ""

    # Page 2 (with cursor from page 1)
    conn_page_2 =
      conn
      |> assign(:current_user, agent)
      |> TreatmentQueueController.index(%{"limit" => "1", "cursor" => next_cursor})

    assert %{
             "items" => [page_2_item],
             "pagination" => %{
               "limit" => 1
             }
           } = json_response(conn_page_2, 200)

    assert page_1_item["treatment_id"] != page_2_item["treatment_id"]
  end

  test "returns 400 when limit is invalid", %{conn: conn, agent: agent} do
    for invalid_limit <- ["0", "101", "-5", "abc"] do
      conn_test =
        conn
        |> assign(:current_user, agent)
        |> TreatmentQueueController.index(%{"limit" => invalid_limit})

      assert %{"error" => "invalid_limit"} = json_response(conn_test, 400)
    end
  end

  test "returns 400 when cursor is invalid", %{conn: conn, agent: agent} do
    conn =
      conn
      |> assign(:current_user, agent)
      |> TreatmentQueueController.index(%{"cursor" => "invalid_not_base64"})

    assert %{"error" => "invalid_cursor"} = json_response(conn, 400)
  end

  test "requires authentication for the queue route", %{conn: conn} do
    conn = get(conn, ~p"/api/treatments/queue")

    assert response(conn, 401)
  end

  defp logistics_agent_fixture(prefix) do
    %User{}
    |> User.auth_changeset(%{
      email: "#{prefix}-#{System.unique_integer([:positive])}@example.com",
      username: "#{prefix}-#{System.unique_integer([:positive])}",
      role: "logistics_agent"
    })
    |> Repo.insert!()
  end
end
