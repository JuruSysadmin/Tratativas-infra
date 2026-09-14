defmodule ChatWeb.TreatmentAssignmentControllerTest do
  use ChatWeb.ConnCase, async: false

  alias Chat.Accounts.User
  alias Chat.Auth.Identity
  alias Chat.Repo
  alias Chat.Rooms
  alias Chat.Treatments
  alias ChatWeb.TreatmentAssignmentController

  test "assigns an open treatment before joining its room", %{conn: conn} do
    {:ok, owner} = Identity.sync_user(%{"sub" => "assignment-owner"}, %{})
    agent = logistics_agent_fixture()
    {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_045_001, owner.id)

    refute Rooms.room_member?(agent.id, treatment.room_id)

    conn =
      conn
      |> assign(:current_user, agent)
      |> TreatmentAssignmentController.create(%{"treatment_id" => treatment.id})

    assert %{
             "treatment_id" => treatment_id,
             "status" => "in_progress",
             "assigned_agent_id" => assigned_agent_id,
             "sla_paused_seconds" => 0
           } = json_response(conn, 200)

    assert treatment_id == treatment.id
    assert assigned_agent_id == agent.id
    assert Rooms.room_member?(agent.id, treatment.room_id)
  end

  test "broadcasts only after a successful assignment commit", %{conn: conn} do
    {:ok, owner} = Identity.sync_user(%{"sub" => "broadcast-owner"}, %{})
    agent = logistics_agent_fixture()
    {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_045_002, owner.id)
    Phoenix.PubSub.subscribe(Chat.PubSub, "room:#{treatment.room_id}")

    conn =
      conn
      |> assign(:current_user, agent)
      |> TreatmentAssignmentController.create(%{"treatment_id" => treatment.id})

    assert response(conn, 200)
    assert_receive {:treatment_assigned, payload}
    assert payload.treatment_id == treatment.id
    assert Repo.get!(Chat.Treatments.Treatment, treatment.id).status == "in_progress"
  end

  test "notifies the treatment creator when logistics assumes it", %{conn: conn} do
    {:ok, owner} = Identity.sync_user(%{"sub" => "assignment-notification-owner"}, %{})
    agent = logistics_agent_fixture()
    {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_045_006, owner.id)
    Phoenix.PubSub.subscribe(Chat.PubSub, "user:#{owner.id}")
    Phoenix.PubSub.subscribe(Chat.PubSub, "user:#{agent.id}")

    conn =
      conn
      |> assign(:current_user, agent)
      |> TreatmentAssignmentController.create(%{"treatment_id" => treatment.id})

    assert response(conn, 200)
    assert_receive {:treatment_assigned, payload}
    assert payload.treatment_id == treatment.id
    assert payload.room_id == treatment.room_id
    refute_receive {:treatment_assigned, _payload}
  end

  test "broadcasts the canonical treatment update to the queue topic", %{conn: conn} do
    {:ok, owner} = Identity.sync_user(%{"sub" => "queue-update-owner"}, %{})
    agent = logistics_agent_fixture()
    {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_045_005, owner.id)
    Phoenix.PubSub.subscribe(Chat.PubSub, "treatments:queue")

    conn =
      conn
      |> assign(:current_user, agent)
      |> TreatmentAssignmentController.create(%{"treatment_id" => treatment.id})

    assert response(conn, 200)

    assert_receive %Phoenix.Socket.Broadcast{
      topic: "treatments:queue",
      event: "treatment:updated",
      payload: payload
    }

    assert payload.treatment_id == treatment.id
    assert payload.status == "in_progress"
    assert payload.assigned_agent_id == agent.id
    assert payload.order_id == 9_998_045_005
    assert payload.can_assign == false
  end

  test "commercial users cannot assign a treatment", %{conn: conn} do
    {:ok, owner} = Identity.sync_user(%{"sub" => "commercial-assignment-owner"}, %{})
    {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_045_003, owner.id)

    conn =
      conn
      |> assign(:current_user, owner)
      |> TreatmentAssignmentController.create(%{"treatment_id" => treatment.id})

    assert %{"error" => "forbidden"} = json_response(conn, 403)
    assert Repo.get!(Chat.Treatments.Treatment, treatment.id).status == "open"
  end

  test "returns conflict when another agent already owns the treatment", %{conn: conn} do
    {:ok, owner} = Identity.sync_user(%{"sub" => "conflict-owner"}, %{})
    first_agent = logistics_agent_fixture()
    second_agent = logistics_agent_fixture()
    {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_045_004, owner.id)

    assert {:ok, _assigned} = Treatments.assign_agent(treatment, first_agent)

    conn =
      conn
      |> assign(:current_user, second_agent)
      |> TreatmentAssignmentController.create(%{"treatment_id" => treatment.id})

    assert %{"error" => "already_assigned"} = json_response(conn, 409)
  end

  test "requires authentication on the HTTP route", %{conn: conn} do
    conn = post(conn, "/api/treatments/#{Ecto.UUID.generate()}/assign-to-me")

    assert response(conn, 401)
  end

  defp logistics_agent_fixture do
    %User{}
    |> User.auth_changeset(%{
      email: "assignment-agent-#{System.unique_integer([:positive])}@example.com",
      username: "assignment-agent-#{System.unique_integer([:positive])}",
      role: "logistics_agent"
    })
    |> Repo.insert!()
  end
end
