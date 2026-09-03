defmodule ChatWeb.TreatmentQueueChannelTest do
  use Chat.DataCase, async: false

  import Phoenix.ChannelTest

  alias Chat.Accounts.User
  alias Chat.Auth.Identity
  alias Chat.Repo
  alias Chat.Rooms
  alias Chat.Treatments
  alias Chat.Treatments.Reason
  alias ChatWeb.RoomChannel
  alias ChatWeb.TreatmentQueueChannel
  alias ChatWeb.UserSocket

  @endpoint ChatWeb.Endpoint

  test "logistics agent can join the global treatment queue" do
    agent = logistics_agent_fixture()

    assert {:ok, %{}, _socket} =
             UserSocket
             |> socket("treatment-queue-agent", %{current_user: agent})
             |> subscribe_and_join(TreatmentQueueChannel, "treatments:queue")
  end

  test "commercial user cannot join the global treatment queue" do
    {:ok, commercial} = Identity.sync_user(%{"sub" => "treatment-queue-commercial"}, %{})

    assert {:error, %{reason: "forbidden"}} =
             UserSocket
             |> socket("treatment-queue-commercial", %{current_user: commercial})
             |> subscribe_and_join(TreatmentQueueChannel, "treatments:queue")
  end

  test "all connected logistics agents receive a newly created treatment" do
    {:ok, commercial} = Identity.sync_user(%{"sub" => "queue-treatment-owner"}, %{})
    reason = reason_fixture()
    first_agent = logistics_agent_fixture()
    second_agent = logistics_agent_fixture()

    for {socket_id, agent} <- [
          {"first-queue-agent", first_agent},
          {"second-queue-agent", second_agent}
        ] do
      assert {:ok, %{}, _socket} =
               UserSocket
               |> socket(socket_id, %{current_user: agent})
               |> subscribe_and_join(TreatmentQueueChannel, "treatments:queue")
    end

    order_id = 9_998_046_001

    assert {:ok, %{treatment: treatment}} =
             Treatments.open_structured_for_order(order_id, commercial.id, %{
               reason_code: reason.code,
               initial_description: "Pedido ainda nao foi entregue."
             })

    assert_push "treatment:created", first_payload
    assert_push "treatment:created", second_payload
    assert first_payload == second_payload

    assert %{
             treatment_id: treatment_id,
             room_id: room_id,
             order_id: ^order_id,
             protocol: protocol,
             status: "open",
             assigned_agent_id: nil,
             assigned_agent_name: nil,
             can_assign: true,
             assigned_at: nil,
             inserted_at: inserted_at,
             reason: %{code: reason_code, label: "Entrega"}
           } = first_payload

    assert reason_code == reason.code
    assert treatment_id == treatment.id
    assert room_id == treatment.room_id
    assert is_binary(protocol)
    assert inserted_at != nil
  end

  test "opening an unstructured treatment also notifies the queue" do
    {:ok, commercial} = Identity.sync_user(%{"sub" => "queue-simple-owner"}, %{})
    agent = logistics_agent_fixture()

    assert {:ok, %{}, _socket} =
             UserSocket
             |> socket("simple-queue-agent", %{current_user: agent})
             |> subscribe_and_join(TreatmentQueueChannel, "treatments:queue")

    assert {:ok, %{treatment: treatment}} =
             Treatments.open_for_order(9_998_046_002, commercial.id)

    assert_push "treatment:created", %{treatment_id: treatment_id, reason: nil, status: "open"}
    assert treatment_id == treatment.id
  end

  test "opening an existing treatment does not notify it as new" do
    {:ok, commercial} = Identity.sync_user(%{"sub" => "queue-existing-owner"}, %{})
    agent = logistics_agent_fixture()
    order_id = 9_998_046_003

    assert {:ok, _} = Treatments.open_for_order(order_id, commercial.id)

    assert {:ok, %{}, _socket} =
             UserSocket
             |> socket("existing-queue-agent", %{current_user: agent})
             |> subscribe_and_join(TreatmentQueueChannel, "treatments:queue")

    assert {:ok, %{treatment: _treatment}} = Treatments.open_for_order(order_id, commercial.id)
    refute_push "treatment:created", _payload
  end

  test "queue subscribers receive treatment updates when a room transition happens" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "queue-transition-owner"}, %{})
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_046_004, owner.id)

    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)

    assert {:ok, %{}, _queue_socket} =
             UserSocket
             |> socket("queue-transition-agent", %{current_user: agent})
             |> subscribe_and_join(TreatmentQueueChannel, "treatments:queue")

    {:ok, _reply, room_socket} =
      UserSocket
      |> socket("queue-transition-room", %{current_user: agent})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref = push(room_socket, "treatment:assign_to_me", %{})

    assert_reply ref, :ok, %{treatment_id: treatment_id}
    assert treatment_id == treatment.id

    assert_push "treatment:updated", payload
    assert payload.treatment_id == treatment.id
    assert payload.status == "in_progress"
    assert payload.assigned_agent_id == agent.id
    assert payload.order_id == 9_998_046_004
  end

  defp logistics_agent_fixture do
    %User{}
    |> User.auth_changeset(%{
      email: "queue-agent-#{System.unique_integer([:positive])}@example.com",
      username: "queue-agent-#{System.unique_integer([:positive])}",
      role: "logistics_agent"
    })
    |> Repo.insert!()
  end

  defp reason_fixture do
    suffix = System.unique_integer([:positive])

    %Reason{}
    |> Reason.changeset(%{
      code: "queue-reason-#{suffix}",
      label: "Entrega",
      priority: "high",
      active: true,
      sort_order: suffix
    })
    |> Repo.insert!()
  end
end
