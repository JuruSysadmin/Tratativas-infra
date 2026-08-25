defmodule ChatWeb.TreatmentQueueControllerTest do
  use ChatWeb.ConnCase, async: true

  alias Chat.Accounts.User
  alias Chat.Auth.Identity
  alias Chat.Repo
  alias Chat.Rooms
  alias Chat.Treatments
  alias Chat.Treatments.Reason
  alias ChatWeb.TreatmentQueueController

  setup do
    {:ok, owner} = Identity.sync_user(%{"sub" => "owner-commercial"}, %{})
    agent = logistics_agent_fixture("agent-queue")

    assert {:ok, %{treatment: treatment_1, room: room_1}} =
             Treatments.open_for_order(9_998_044_301, owner.id)

    assert {:ok, %{treatment: treatment_2, room: room_2}} =
             Treatments.open_for_order(9_998_044_302, owner.id)

    %{
      owner: owner,
      agent: agent,
      treatment_1: treatment_1,
      treatment_2: treatment_2,
      room_1: room_1,
      room_2: room_2
    }
  end

  test "lists eligible open treatments for logistics without granting room membership", %{
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

    refute Rooms.room_member?(agent.id, room_1.id)
    refute Rooms.room_member?(agent.id, room_2.id)

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
    assert first_item["can_assign"] == true
    refute Map.has_key?(first_item, "messages")
    refute Map.has_key?(first_item, "attachments")
  end

  test "includes the structured treatment reason in queue items", %{
    conn: conn,
    agent: agent,
    treatment_1: treatment_1
  } do
    reason =
      %Reason{}
      |> Reason.changeset(%{code: "DELIVERY", label: "Entrega", active: true, sort_order: 1})
      |> Repo.insert!()

    treatment_1
    |> Ecto.Changeset.change(treatment_reason_id: reason.id)
    |> Repo.update!()

    conn =
      conn
      |> assign(:current_user, agent)
      |> TreatmentQueueController.index(%{})

    item =
      conn
      |> json_response(200)
      |> Map.fetch!("items")
      |> Enum.find(&(&1["treatment_id"] == treatment_1.id))

    assert item["reason"] == %{"code" => "DELIVERY", "label" => "Entrega"}
  end

  test "lists only the current logistics agent's in-progress treatment", %{
    conn: conn,
    owner: owner,
    agent: agent,
    treatment_1: treatment_1,
    treatment_2: treatment_2
  } do
    other_agent = logistics_agent_fixture("other-agent-queue")

    assert {:ok, _assigned} = Treatments.assign_agent(treatment_1, agent)
    assert {:ok, _assigned} = Treatments.assign_agent(treatment_2, other_agent)

    conn =
      conn
      |> assign(:current_user, agent)
      |> TreatmentQueueController.index(%{})

    assert %{"items" => [item]} = json_response(conn, 200)
    assert item["treatment_id"] == treatment_1.id
    assert item["assigned_agent_id"] == agent.id
    assert item["can_assign"] == false
    refute Rooms.room_member?(agent.id, treatment_2.room_id)
    assert owner.id != agent.id
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

  test "filters queue by search query matching order_id or protocol", %{
    conn: conn,
    agent: agent,
    treatment_1: treatment_1,
    treatment_2: _treatment_2
  } do
    # Search by exact order_id
    conn_order =
      conn
      |> assign(:current_user, agent)
      |> TreatmentQueueController.index(%{"search" => "9998044301"})

    assert %{"items" => items_order} = json_response(conn_order, 200)
    assert length(items_order) == 1
    assert List.first(items_order)["order_id"] == 9_998_044_301

    # Search by partial order_id
    conn_partial =
      conn
      |> assign(:current_user, agent)
      |> TreatmentQueueController.index(%{"search" => "44302"})

    assert %{"items" => items_partial} = json_response(conn_partial, 200)
    assert length(items_partial) == 1
    assert List.first(items_partial)["order_id"] == 9_998_044_302

    # Search by protocol
    protocol = Treatments.protocol(treatment_1)

    conn_proto =
      conn
      |> assign(:current_user, agent)
      |> TreatmentQueueController.index(%{"search" => protocol})

    assert %{"items" => items_proto} = json_response(conn_proto, 200)
    assert length(items_proto) == 1
    assert List.first(items_proto)["treatment_id"] == treatment_1.id
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
