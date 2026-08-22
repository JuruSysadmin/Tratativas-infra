defmodule ChatWeb.TreatmentTransferAgentControllerTest do
  use ChatWeb.ConnCase, async: true

  alias Chat.Accounts.User
  alias Chat.Auth.Identity
  alias Chat.Repo
  alias Chat.Rooms
  alias Chat.Treatments
  alias ChatWeb.TreatmentTransferAgentController

  setup do
    {:ok, owner} = Identity.sync_user(%{"sub" => "owner-commercial"}, %{})
    agent_a = logistics_agent_fixture("agent-a")
    agent_b = logistics_agent_fixture("agent-b")
    agent_c = logistics_agent_fixture("agent-c")
    outsider_agent = logistics_agent_fixture("outsider-agent")

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_201, owner.id)

    assert {:ok, _} = Rooms.join_room(agent_a.id, room.id)
    assert {:ok, _} = Rooms.join_room(agent_b.id, room.id)
    assert {:ok, _} = Rooms.join_room(agent_c.id, room.id)

    %{
      owner: owner,
      agent_a: agent_a,
      agent_b: agent_b,
      agent_c: agent_c,
      outsider_agent: outsider_agent,
      room: room,
      treatment: treatment
    }
  end

  test "returns 200 with eligible transfer agents for assigned logistics agent", %{
    conn: conn,
    agent_a: agent_a,
    agent_b: agent_b,
    agent_c: agent_c,
    room: room,
    treatment: treatment
  } do
    assert {:ok, _assigned} = Treatments.assign_agent(treatment, agent_a)

    conn =
      conn
      |> assign(:current_user, agent_a)
      |> TreatmentTransferAgentController.index(%{"room_id" => room.id})

    assert %{"agents" => agents} = json_response(conn, 200)
    assert length(agents) == 2

    agent_ids = Enum.map(agents, & &1["id"])
    assert agent_b.id in agent_ids
    assert agent_c.id in agent_ids
    refute agent_a.id in agent_ids

    for agent <- agents do
      assert Map.has_key?(agent, "id")
      assert Map.has_key?(agent, "username")
    end
  end

  test "returns 200 with empty array %{agents: []} when no eligible candidates exist in the room",
       %{conn: conn, agent_a: agent_a, owner: owner} do
    assert {:ok, %{treatment: single_agent_treatment, room: single_agent_room}} =
             Treatments.open_for_order(9_998_044_299, owner.id)

    assert {:ok, _} = Rooms.join_room(agent_a.id, single_agent_room.id)
    assert {:ok, _assigned} = Treatments.assign_agent(single_agent_treatment, agent_a)

    conn =
      conn
      |> assign(:current_user, agent_a)
      |> TreatmentTransferAgentController.index(%{"room_id" => single_agent_room.id})

    assert %{"agents" => []} = json_response(conn, 200)
  end

  test "returns 403 not_assigned_agent when requested by another logistics agent in the room", %{
    conn: conn,
    agent_a: agent_a,
    agent_b: agent_b,
    room: room,
    treatment: treatment
  } do
    assert {:ok, _assigned} = Treatments.assign_agent(treatment, agent_a)

    conn =
      conn
      |> assign(:current_user, agent_b)
      |> TreatmentTransferAgentController.index(%{"room_id" => room.id})

    assert %{"error" => "not_assigned_agent"} = json_response(conn, 403)
  end

  test "returns 403 not_authorized when requested by non-member agent", %{
    conn: conn,
    agent_a: agent_a,
    outsider_agent: outsider_agent,
    room: room,
    treatment: treatment
  } do
    assert {:ok, _assigned} = Treatments.assign_agent(treatment, agent_a)

    conn =
      conn
      |> assign(:current_user, outsider_agent)
      |> TreatmentTransferAgentController.index(%{"room_id" => room.id})

    assert %{"error" => "not_authorized"} = json_response(conn, 403)
  end

  test "returns 422 invalid_status when treatment is open or resolved", %{
    conn: conn,
    agent_a: agent_a,
    room: room,
    treatment: treatment
  } do
    # When open
    conn_open =
      conn
      |> assign(:current_user, agent_a)
      |> TreatmentTransferAgentController.index(%{"room_id" => room.id})

    assert %{"error" => "invalid_status"} = json_response(conn_open, 422)

    # When resolved
    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent_a)
    assert {:ok, _resolved} = Treatments.resolve(assigned, agent_a)

    conn_resolved =
      conn
      |> assign(:current_user, agent_a)
      |> TreatmentTransferAgentController.index(%{"room_id" => room.id})

    assert %{"error" => "invalid_status"} = json_response(conn_resolved, 422)
  end

  test "returns 404 when room does not exist", %{conn: conn, agent_a: agent_a} do
    conn =
      conn
      |> assign(:current_user, agent_a)
      |> TreatmentTransferAgentController.index(%{"room_id" => Ecto.UUID.generate()})

    assert %{"error" => "not_found"} = json_response(conn, 404)
  end

  test "returns 400 when room_id is invalid", %{conn: conn, agent_a: agent_a} do
    conn =
      conn
      |> assign(:current_user, agent_a)
      |> TreatmentTransferAgentController.index(%{"room_id" => "invalid-uuid"})

    assert %{"error" => "invalid_id"} = json_response(conn, 400)
  end

  test "requires authentication for the transfer-agents route", %{conn: conn, room: room} do
    conn = get(conn, ~p"/api/rooms/#{room.id}/transfer-agents")

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
