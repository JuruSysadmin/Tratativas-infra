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

  test "returns 200 with queue items accessible to the agent", %{
    conn: conn,
    agent: agent,
    room_1: room_1,
    room_2: room_2
  } do
    conn =
      conn
      |> assign(:current_user, agent)
      |> TreatmentQueueController.index(%{})

    assert %{"items" => items} = json_response(conn, 200)
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
