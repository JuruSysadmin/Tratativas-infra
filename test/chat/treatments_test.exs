defmodule Chat.TreatmentsTest do
  use Chat.DataCase, async: false

  alias Chat.Accounts.User
  alias Chat.Auth.Identity
  alias Chat.Repo
  alias Chat.Rooms
  alias Chat.Treatments
  alias Chat.Treatments.Treatment
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    {:ok, user} = Identity.sync_user(%{"sub" => "treatment-owner"}, %{})
    %{user: user}
  end

  test "creates one treatment with a sequential protocol and audit event", %{user: user} do
    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_043_470, user.id)

    assert treatment.order_id == 9_998_043_470
    assert treatment.room_id == room.id
    assert treatment.protocol_number > 0
    assert treatment.status == "open"

    assert [%{event_type: "treatment_created", actor_id: actor_id}] =
             Treatments.list_audit_events(treatment.id, user.id)

    assert actor_id == user.id
  end

  test "opens a treatment with a catalogued reason and initial description", %{user: user} do
    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_structured_for_order(9_998_043_471, user.id, %{
               reason_code: "delivery",
               initial_description: "Pedido ainda nao foi entregue ao cliente."
             })

    assert treatment.status == "open"
    assert treatment.assigned_agent_id == nil
    assert treatment.room_id == room.id
    assert treatment.reason.code == "delivery"
    assert treatment.reason.label == "Entrega"
    assert treatment.initial_description == "Pedido ainda nao foi entregue ao cliente."
  end

  test "reports a missing treatment with active intake reasons" do
    assert {:missing, reasons} = Treatments.intake_state(9_998_043_469)

    assert Enum.map(reasons, &{&1.code, &1.label}) == [
             {"delivery", "Entrega"},
             {"stock", "Estoque"},
             {"billing", "Faturamento"},
             {"product", "Produto"},
             {"cancellation", "Cancelamento"},
             {"divergence", "Divergência"},
             {"other", "Outro"}
           ]
  end

  test "treatment can exist without an assigned agent", %{user: user} do
    assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_043_472, user.id)

    assert treatment.assigned_agent_id == nil
    assert treatment.assigned_at == nil
  end

  test "opening a closed treatment preserves its terminal state for an authorized member", %{
    user: user
  } do
    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_045_010, user.id)

    assert {:ok, closed} = Treatments.close(treatment, user.id)
    assert closed.status == "closed"

    assert {:ok, %{treatment: reopened, room: reopened_room}} =
             Treatments.open_for_order(treatment.order_id, user.id)

    assert reopened.id == treatment.id
    assert reopened_room.id == room.id
    assert reopened.status == "closed"
    assert audit_event_count(treatment, user, "treatment_reopened") == 0
  end

  test "opening a closed treatment does not grant membership to an unauthorized user", %{
    user: user
  } do
    {:ok, outsider} = Identity.sync_user(%{"sub" => "closed-treatment-outsider"}, %{})

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_045_011, user.id)

    assert {:ok, _closed} = Treatments.close(treatment, user.id)
    refute Rooms.room_member?(outsider.id, room.id)

    assert {:error, :forbidden} = Treatments.open_for_order(treatment.order_id, outsider.id)
    refute Rooms.room_member?(outsider.id, room.id)
    assert audit_event_count(treatment, user, "treatment_reopened") == 0
  end

  test "closed treatment rejects another close operation", %{user: user} do
    assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_045_012, user.id)
    assert {:ok, _closed} = Treatments.close(treatment, user.id)

    assert {:error, :invalid_status} = Treatments.close(treatment, user.id)
    assert audit_event_count(treatment, user, "treatment_closed") == 1
  end

  test "gets a treatment by room id", %{user: user} do
    assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_043_499, user.id)

    assert %Treatment{id: treatment_id} = Treatments.get_by_room_id(treatment.room_id)
    assert treatment_id == treatment.id
    assert Treatments.get_by_room_id(Ecto.UUID.generate()) == nil
  end

  test "logistics agent can assign an available treatment", %{user: user} do
    agent = logistics_agent_fixture()
    assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_043_480, user.id)

    assert Repo.get_by(Chat.Rooms.RoomMember, user_id: agent.id, room_id: treatment.room_id) ==
             nil

    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)

    assert assigned.assigned_agent_id == agent.id
    assert assigned.assigned_at != nil
    assert assigned.status == "in_progress"

    assert Rooms.room_member?(agent.id, treatment.room_id)

    assert Repo.get!(Treatment, treatment.id).status == "in_progress"

    agent_id = agent.id

    assert [
             %{event_type: "treatment_assigned", actor_id: ^agent_id},
             %{event_type: "treatment_created", actor_id: _owner_id}
           ] =
             Treatments.list_audit_events(treatment.id, user.id)
  end

  test "assigned agent can unassign an in-progress treatment", %{user: user} do
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_043_512, user.id)

    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)

    assert {:ok, unassigned, :unassigned} = Treatments.unassign(assigned, agent)
    assert unassigned.status == "open"
    assert unassigned.assigned_agent_id == nil
    assert unassigned.assigned_at == nil

    assert %{status: "open", assigned_agent_id: nil, assigned_at: nil} =
             Repo.get!(Treatment, treatment.id)

    assert audit_event_count(treatment, user, "treatment_unassigned") == 1
  end

  test "assigned agent can transfer an in-progress treatment to another logistics member", %{
    user: user
  } do
    current_agent = logistics_agent_fixture()
    target_agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_043_530, user.id)

    assert {:ok, _membership} = Rooms.join_room(current_agent.id, room.id)
    assert {:ok, _membership} = Rooms.join_room(target_agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, current_agent)

    assert {:ok, transferred, :transferred} =
             Treatments.transfer_agent(assigned, current_agent, target_agent)

    assert transferred.status == "in_progress"
    assert transferred.assigned_agent_id == target_agent.id
    assert DateTime.compare(transferred.assigned_at, assigned.assigned_at) == :gt

    target_agent_id = target_agent.id

    assert %{status: "in_progress", assigned_agent_id: ^target_agent_id} =
             Repo.get!(Treatment, treatment.id)

    assert [event | _] = Treatments.list_audit_events(treatment.id, user.id)
    assert event.event_type == "treatment_transferred"
    assert event.actor_id == current_agent.id
    assert event.metadata["previous_agent_id"] == current_agent.id
    assert event.metadata["assigned_agent_id"] == target_agent.id
  end

  test "transfer preserves the current membership and grants the target access", %{user: user} do
    current_agent = logistics_agent_fixture()
    target_agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_045_006, user.id)

    assert {:ok, _membership} = Rooms.join_room(current_agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, current_agent)
    refute Rooms.room_member?(target_agent.id, room.id)

    assert {:ok, transferred, :transferred} =
             Treatments.transfer_agent(assigned, current_agent, target_agent)

    assert transferred.assigned_agent_id == target_agent.id
    assert Rooms.room_member?(current_agent.id, room.id)
    assert Rooms.room_member?(target_agent.id, room.id)
  end

  test "stale former owner cannot close after transfer", %{user: user} do
    current_agent = logistics_agent_fixture()
    target_agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_045_008, user.id)

    assert {:ok, _membership} = Rooms.join_room(current_agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, current_agent)

    assert {:ok, _transferred, :transferred} =
             Treatments.transfer_agent(assigned, current_agent, target_agent)

    assert {:error, :not_assigned_agent} = Treatments.close(assigned, current_agent.id)
    assert Repo.get!(Treatment, treatment.id).status == "in_progress"
  end

  test "transfer rolls back a new target membership when audit persistence fails", %{user: user} do
    current_agent = logistics_agent_fixture()
    target_agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_045_009, user.id)

    assert {:ok, _membership} = Rooms.join_room(current_agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, current_agent)
    assert Repo.get_by(Chat.Rooms.RoomMember, user_id: target_agent.id, room_id: room.id) == nil

    previous_inserter = Application.get_env(:chat, :treatment_audit_event_inserter)

    Application.put_env(
      :chat,
      :treatment_audit_event_inserter,
      Chat.TestSupport.FailingTreatmentAuditEventInserter
    )

    on_exit(fn -> restore_env(:treatment_audit_event_inserter, previous_inserter) end)

    assert {:error, %Ecto.Changeset{}} =
             Treatments.transfer_agent(assigned, current_agent, target_agent)

    assert Repo.get!(Treatment, treatment.id).assigned_agent_id == current_agent.id
    assert Repo.get_by(Chat.Rooms.RoomMember, user_id: target_agent.id, room_id: room.id) == nil
  end

  test "commercial user cannot transfer a treatment", %{user: user} do
    current_agent = logistics_agent_fixture()
    target_agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_043_531, user.id)

    assert {:ok, _membership} = Rooms.join_room(current_agent.id, room.id)
    assert {:ok, _membership} = Rooms.join_room(target_agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, current_agent)

    assert {:error, :forbidden} = Treatments.transfer_agent(assigned, user, target_agent)
    assert Repo.get!(Treatment, treatment.id).assigned_agent_id == current_agent.id
    assert audit_event_count(treatment, user, "treatment_transferred") == 0
  end

  test "only the assigned agent can transfer a treatment", %{user: user} do
    current_agent = logistics_agent_fixture()
    other_agent = logistics_agent_fixture()
    target_agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_043_532, user.id)

    for agent <- [current_agent, other_agent, target_agent] do
      assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
    end

    assert {:ok, assigned} = Treatments.assign_agent(treatment, current_agent)

    assert {:error, :not_assigned_agent} =
             Treatments.transfer_agent(assigned, other_agent, target_agent)
  end

  test "target must be another logistics agent", %{user: user} do
    current_agent = logistics_agent_fixture()
    target_agent = logistics_agent_fixture()
    missing_target = %User{id: Ecto.UUID.generate(), role: "logistics_agent"}

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_043_533, user.id)

    assert {:ok, _membership} = Rooms.join_room(current_agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, current_agent)

    assert {:ok, transferred, :transferred} =
             Treatments.transfer_agent(assigned, current_agent, target_agent)

    assert transferred.assigned_agent_id == target_agent.id
    assert Rooms.room_member?(target_agent.id, room.id)

    assert {:error, :invalid_target_agent} =
             Treatments.transfer_agent(transferred, target_agent, user)

    assert {:error, :invalid_target_agent} =
             Treatments.transfer_agent(transferred, target_agent, missing_target)

    assert {:error, :same_agent} =
             Treatments.transfer_agent(transferred, target_agent, target_agent)
  end

  test "current agent outside the room receives not_found", %{user: user} do
    current_agent = logistics_agent_fixture()
    target_agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_043_534, user.id)

    assert {:ok, _membership} = Rooms.join_room(current_agent.id, room.id)
    assert {:ok, _membership} = Rooms.join_room(target_agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, current_agent)
    assert {:ok, 1} = Rooms.leave_room(current_agent.id, room.id)

    assert {:error, :not_found} =
             Treatments.transfer_agent(assigned, current_agent, target_agent)
  end

  test "only in-progress treatments can be transferred", %{user: user} do
    current_agent = logistics_agent_fixture()
    target_agent = logistics_agent_fixture()

    for {status, order_id} <- [
          {"open", 9_998_043_535},
          {"resolved", 9_998_043_536},
          {"closed", 9_998_043_537}
        ] do
      assert {:ok, %{treatment: treatment, room: room}} =
               Treatments.open_for_order(order_id, user.id)

      for agent <- [current_agent, target_agent] do
        assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
      end

      treatment =
        case status do
          "open" ->
            treatment

          "resolved" ->
            {:ok, assigned} = Treatments.assign_agent(treatment, current_agent)
            {:ok, resolved} = Treatments.resolve(assigned, current_agent)
            resolved

          "closed" ->
            {:ok, closed} = Treatments.close(treatment, user.id)
            closed
        end

      assert {:error, :invalid_status} =
               Treatments.transfer_agent(treatment, current_agent, target_agent)
    end
  end

  test "stale caller state cannot transfer a treatment", %{user: user} do
    current_agent = logistics_agent_fixture()
    other_agent = logistics_agent_fixture()
    target_agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_043_538, user.id)

    for agent <- [current_agent, other_agent, target_agent] do
      assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
    end

    assert {:ok, assigned} = Treatments.assign_agent(treatment, current_agent)

    assert {:ok, _transferred} =
             assigned
             |> Treatment.transfer_changeset(other_agent.id, DateTime.utc_now())
             |> Repo.update()

    assert {:error, :not_assigned_agent} =
             Treatments.transfer_agent(assigned, current_agent, target_agent)
  end

  test "transfer rolls back when the audit event cannot be persisted", %{user: user} do
    current_agent = logistics_agent_fixture()
    target_agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_043_539, user.id)

    assert {:ok, _membership} = Rooms.join_room(current_agent.id, room.id)
    assert {:ok, _membership} = Rooms.join_room(target_agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, current_agent)
    previous_inserter = Application.get_env(:chat, :treatment_audit_event_inserter)

    Application.put_env(
      :chat,
      :treatment_audit_event_inserter,
      Chat.TestSupport.FailingTreatmentAuditEventInserter
    )

    on_exit(fn -> restore_env(:treatment_audit_event_inserter, previous_inserter) end)

    assert {:error, %Ecto.Changeset{}} =
             Treatments.transfer_agent(assigned, current_agent, target_agent)

    current_agent_id = current_agent.id

    assert %{status: "in_progress", assigned_agent_id: ^current_agent_id} =
             Repo.get!(Treatment, treatment.id)
  end

  test "commercial user cannot unassign a treatment", %{user: user} do
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_043_513, user.id)

    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)

    assert {:error, :forbidden} = Treatments.unassign(assigned, user)
    assert Repo.get!(Treatment, treatment.id).status == "in_progress"
    assert audit_event_count(treatment, user, "treatment_unassigned") == 0
  end

  test "another logistics agent cannot unassign a treatment", %{user: user} do
    assigned_agent = logistics_agent_fixture()
    other_agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_043_514, user.id)

    assert {:ok, _membership} = Rooms.join_room(assigned_agent.id, room.id)
    assert {:ok, _membership} = Rooms.join_room(other_agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, assigned_agent)

    assert {:error, :not_assigned_agent} = Treatments.unassign(assigned, other_agent)

    assert %{
             status: "in_progress",
             assigned_agent_id: assigned_agent_id,
             assigned_at: assigned_at
           } =
             Repo.get!(Treatment, treatment.id)

    assert assigned_agent_id == assigned_agent.id
    assert assigned_at == assigned.assigned_at
    assert audit_event_count(treatment, user, "treatment_unassigned") == 0
  end

  test "authorized agent outside the room receives not_found", %{user: user} do
    assigned_agent = logistics_agent_fixture()
    outsider = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_043_515, user.id)

    assert {:ok, _membership} = Rooms.join_room(assigned_agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, assigned_agent)

    assert {:error, :not_found} = Treatments.unassign(assigned, outsider)
    assert Repo.get!(Treatment, treatment.id).status == "in_progress"
    assert Repo.get!(Treatment, treatment.id).assigned_agent_id == assigned_agent.id
    assert audit_event_count(treatment, user, "treatment_unassigned") == 0
  end

  test "only in-progress treatments can be unassigned", %{user: user} do
    agent = logistics_agent_fixture()

    for {status, order_id} <- [
          {"open", 9_998_043_516},
          {"resolved", 9_998_043_517},
          {"closed", 9_998_043_518}
        ] do
      assert {:ok, %{treatment: treatment, room: room}} =
               Treatments.open_for_order(order_id, user.id)

      assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)

      treatment =
        case status do
          "open" ->
            treatment

          "resolved" ->
            {:ok, assigned} = Treatments.assign_agent(treatment, agent)
            {:ok, resolved} = Treatments.resolve(assigned, agent)
            resolved

          "closed" ->
            {:ok, closed} = Treatments.close(treatment, user.id)
            closed
        end

      assert {:error, :invalid_status} = Treatments.unassign(treatment, agent)
      assert Repo.get!(Treatment, treatment.id).status == status
      assert audit_event_count(treatment, user, "treatment_unassigned") == 0
    end
  end

  test "unassign rolls back when the audit event cannot be persisted", %{user: user} do
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_043_519, user.id)

    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)
    previous_inserter = Application.get_env(:chat, :treatment_audit_event_inserter)

    Application.put_env(
      :chat,
      :treatment_audit_event_inserter,
      Chat.TestSupport.FailingTreatmentAuditEventInserter
    )

    on_exit(fn -> restore_env(:treatment_audit_event_inserter, previous_inserter) end)

    assert {:error, %Ecto.Changeset{} = changeset} = Treatments.unassign(assigned, agent)
    assert "forced audit failure" in errors_on(changeset).event_type

    assert %{
             status: "in_progress",
             assigned_agent_id: assigned_agent_id,
             assigned_at: assigned_at
           } =
             Repo.get!(Treatment, treatment.id)

    assert assigned_agent_id == assigned.assigned_agent_id
    assert assigned_at == assigned.assigned_at
    assert audit_event_count(treatment, user, "treatment_unassigned") == 0
  end

  test "unassign evaluates persisted state instead of stale caller state", %{user: user} do
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_043_520, user.id)

    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)

    assert {:ok, _persisted_open} =
             assigned
             |> Treatment.unassignment_changeset()
             |> Repo.update()

    assert assigned.status == "in_progress"
    assert Repo.get!(Treatment, treatment.id).status == "open"
    assert {:error, :invalid_status} = Treatments.unassign(assigned, agent)
    assert audit_event_count(treatment, user, "treatment_unassigned") == 0
  end

  test "concurrent unassign allows only one effective transition", %{user: user} do
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_043_521, user.id)

    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)

    tasks =
      for _ <- 1..2 do
        task =
          Task.async(fn ->
            receive do
              :unassign -> Treatments.unassign(assigned, agent)
            end
          end)

        Sandbox.allow(Repo, self(), task.pid)
        task
      end

    Enum.each(tasks, &send(&1.pid, :unassign))

    outcomes =
      tasks
      |> Enum.map(&Task.await(&1, 5_000))
      |> Enum.map(fn
        {:ok, _treatment, :unassigned} -> :unassigned
        {:error, :invalid_status} -> :invalid_status
      end)
      |> Enum.sort()

    assert [:invalid_status, :unassigned] = outcomes

    assert %{status: "open", assigned_agent_id: nil, assigned_at: nil} =
             Repo.get!(Treatment, treatment.id)

    assert audit_event_count(treatment, user, "treatment_unassigned") == 1
  end

  test "unassign returns not_found for a missing treatment", %{user: user} do
    agent = logistics_agent_fixture()

    assert {:ok, %{room: room}} = Treatments.open_for_order(9_998_043_522, user.id)
    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)

    missing_treatment = %Treatment{id: Ecto.UUID.generate(), room_id: room.id}

    assert {:error, :not_found} = Treatments.unassign(missing_treatment, agent)
  end

  test "concurrent transfers allow only one effective transition", %{user: user} do
    current_agent = logistics_agent_fixture()
    first_target = logistics_agent_fixture()
    second_target = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_043_540, user.id)

    for agent <- [current_agent, first_target, second_target] do
      assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
    end

    assert {:ok, assigned} = Treatments.assign_agent(treatment, current_agent)

    tasks =
      for target <- [first_target, second_target] do
        task =
          Task.async(fn ->
            receive do
              :transfer -> Treatments.transfer_agent(assigned, current_agent, target)
            end
          end)

        Sandbox.allow(Repo, self(), task.pid)
        task
      end

    Enum.each(tasks, &send(&1.pid, :transfer))

    outcomes = Enum.map(tasks, &Task.await(&1, 5_000))

    assert Enum.count(outcomes, &match?({:ok, _, :transferred}, &1)) == 1
    assert Enum.count(outcomes, &(&1 == {:error, :not_assigned_agent})) == 1
    assert audit_event_count(treatment, user, "treatment_transferred") == 1

    assert %{status: "in_progress", assigned_agent_id: assigned_agent_id} =
             Repo.get!(Treatment, treatment.id)

    assert assigned_agent_id in [first_target.id, second_target.id]
  end

  test "transfer and unassign allow only one effective transition", %{user: user} do
    current_agent = logistics_agent_fixture()
    target_agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_043_541, user.id)

    assert {:ok, _membership} = Rooms.join_room(current_agent.id, room.id)
    assert {:ok, _membership} = Rooms.join_room(target_agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, current_agent)

    tasks =
      [
        fn -> Treatments.transfer_agent(assigned, current_agent, target_agent) end,
        fn -> Treatments.unassign(assigned, current_agent) end
      ]
      |> Enum.map(fn operation ->
        task =
          Task.async(fn ->
            receive do
              :run -> operation.()
            end
          end)

        Sandbox.allow(Repo, self(), task.pid)
        task
      end)

    Enum.each(tasks, &send(&1.pid, :run))
    outcomes = Enum.map(tasks, &Task.await(&1, 5_000))

    assert Enum.count(outcomes, &match?({:ok, _, _}, &1)) == 1
    assert Enum.count(outcomes, &match?({:error, _}, &1)) == 1

    assert %{
             "treatment_transferred" => transferred_events,
             "treatment_unassigned" => unassigned_events
           } =
             audit_event_counts(treatment, user, ["treatment_transferred", "treatment_unassigned"])

    assert transferred_events + unassigned_events == 1
  end

  test "transfer and resolve allow only one effective transition", %{user: user} do
    current_agent = logistics_agent_fixture()
    target_agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_043_542, user.id)

    assert {:ok, _membership} = Rooms.join_room(current_agent.id, room.id)
    assert {:ok, _membership} = Rooms.join_room(target_agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, current_agent)

    tasks =
      [
        fn -> Treatments.transfer_agent(assigned, current_agent, target_agent) end,
        fn -> Treatments.resolve(assigned, current_agent) end
      ]
      |> Enum.map(fn operation ->
        task =
          Task.async(fn ->
            receive do
              :run -> operation.()
            end
          end)

        Sandbox.allow(Repo, self(), task.pid)
        task
      end)

    Enum.each(tasks, &send(&1.pid, :run))
    outcomes = Enum.map(tasks, &Task.await(&1, 5_000))

    assert Enum.count(outcomes, fn outcome ->
             match?({:ok, _, :transferred}, outcome) or match?({:ok, _}, outcome)
           end) == 1

    assert Enum.count(outcomes, &match?({:error, _}, &1)) == 1

    assert %{
             "treatment_transferred" => transferred_events,
             "treatment_resolved" => resolved_events
           } =
             audit_event_counts(treatment, user, ["treatment_transferred", "treatment_resolved"])

    assert transferred_events + resolved_events == 1
  end

  test "assigned agent can resolve an in-progress treatment", %{user: user} do
    agent = logistics_agent_fixture()
    assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_043_489, user.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)

    assert {:ok, resolved} = Treatments.resolve(assigned, agent)

    assert resolved.status == "resolved"
    assert resolved.resolved_by_id == agent.id
    assert resolved.resolved_at != nil

    assert %{
             status: "resolved",
             resolved_by_id: resolved_by_id,
             resolved_at: resolved_at,
             assigned_agent_id: assigned_agent_id,
             assigned_at: assigned_at
           } = Repo.get!(Treatment, treatment.id)

    assert resolved_by_id == agent.id
    assert resolved_at == resolved.resolved_at
    assert assigned_agent_id == assigned.assigned_agent_id
    assert assigned_at == assigned.assigned_at

    agent_id = agent.id

    assert [
             %{event_type: "treatment_resolved", actor_id: ^agent_id},
             %{event_type: "treatment_assigned", actor_id: ^agent_id},
             %{event_type: "treatment_created", actor_id: _owner_id}
           ] =
             Treatments.list_audit_events(treatment.id, user.id)
  end

  test "commercial user can reopen a resolved treatment", %{user: commercial} do
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment}} =
             Treatments.open_for_order(9_998_043_501, commercial.id)

    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)
    assert {:ok, resolved} = Treatments.resolve(assigned, agent)

    assert {:ok, reopened, :reopened} = Treatments.reopen(resolved, commercial)
    assert reopened.status == "in_progress"
    assert reopened.assigned_agent_id == assigned.assigned_agent_id
    assert reopened.assigned_at == assigned.assigned_at
    assert reopened.resolved_by_id == nil
    assert reopened.resolved_at == nil

    assert {:error, :invalid_status} = Treatments.reopen(resolved, commercial)
    assert audit_event_count(treatment, commercial, "treatment_reopened") == 1
  end

  test "logistics agent can reopen a resolved treatment", %{user: owner} do
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_043_502, owner.id)

    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)
    assert {:ok, resolved} = Treatments.resolve(assigned, agent)

    assert {:ok, reopened, :reopened} = Treatments.reopen(resolved, agent)
    assert reopened.status == "in_progress"
    assert audit_event_count(treatment, owner, "treatment_reopened") == 1
  end

  test "unauthorized role cannot reopen a resolved treatment", %{user: owner} do
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment}} =
             Treatments.open_for_order(9_998_043_503, owner.id)

    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)
    assert {:ok, resolved} = Treatments.resolve(assigned, agent)
    unauthorized = %{owner | role: "unknown"}

    assert {:error, :forbidden} = Treatments.reopen(resolved, unauthorized)

    assert %{status: "resolved", resolved_by_id: resolved_by_id, resolved_at: resolved_at} =
             Repo.get!(Treatment, treatment.id)

    assert resolved_by_id == resolved.resolved_by_id
    assert resolved_at == resolved.resolved_at
    assert audit_event_count(treatment, owner, "treatment_reopened") == 0
  end

  test "authorized user cannot reopen a treatment outside their rooms", %{user: owner} do
    agent = logistics_agent_fixture()

    assert {:ok, outsider} =
             Identity.sync_user(%{"sub" => "treatment-reopen-outsider"}, %{})

    assert outsider.role == "commercial"

    assert {:ok, %{treatment: treatment}} =
             Treatments.open_for_order(9_998_043_510, owner.id)

    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)
    assert {:ok, resolved} = Treatments.resolve(assigned, agent)

    assert {:error, :not_found} = Treatments.reopen(resolved, outsider)

    assert %{
             status: "resolved",
             assigned_agent_id: assigned_agent_id,
             assigned_at: assigned_at,
             resolved_by_id: resolved_by_id,
             resolved_at: resolved_at
           } = Repo.get!(Treatment, treatment.id)

    assert assigned_agent_id == resolved.assigned_agent_id
    assert assigned_at == resolved.assigned_at
    assert resolved_by_id == resolved.resolved_by_id
    assert resolved_at == resolved.resolved_at
    assert audit_event_count(treatment, owner, "treatment_reopened") == 0
  end

  test "reopen_for_room rejects an authorized user outside the room", %{user: owner} do
    agent = logistics_agent_fixture()

    assert {:ok, outsider} =
             Identity.sync_user(%{"sub" => "treatment-reopen-for-room-outsider"}, %{})

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_043_511, owner.id)

    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)
    assert {:ok, resolved} = Treatments.resolve(assigned, agent)

    assert {:error, :not_found} = Treatments.reopen_for_room(room.id, outsider)

    assert Repo.get!(Treatment, treatment.id).status == resolved.status
    assert audit_event_count(treatment, owner, "treatment_reopened") == 0
  end

  test "only resolved treatments can be reopened", %{user: owner} do
    agent = logistics_agent_fixture()

    for {status, order_id} <- [
          {"open", 9_998_043_504},
          {"in_progress", 9_998_043_505},
          {"closed", 9_998_043_506}
        ] do
      assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(order_id, owner.id)

      treatment =
        case status do
          "open" ->
            treatment

          "in_progress" ->
            assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)
            assigned

          "closed" ->
            assert {:ok, closed} = Treatments.close(treatment, owner.id)
            closed
        end

      assert {:error, :invalid_status} = Treatments.reopen(treatment, owner)
      assert Repo.get!(Treatment, treatment.id).status == status
      assert audit_event_count(treatment, owner, "treatment_reopened") == 0
    end
  end

  test "reopen evaluates persisted state instead of stale caller state", %{user: owner} do
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment}} =
             Treatments.open_for_order(9_998_043_507, owner.id)

    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)
    assert {:ok, stale_resolved} = Treatments.resolve(assigned, agent)

    assert {:ok, persisted_closed} =
             stale_resolved
             |> Treatment.changeset(%{status: "closed"})
             |> Repo.update()

    assert stale_resolved.status == "resolved"
    assert persisted_closed.status == "closed"
    assert {:error, :invalid_status} = Treatments.reopen(stale_resolved, owner)
    assert Repo.get!(Treatment, treatment.id).status == "closed"
    assert audit_event_count(treatment, owner, "treatment_reopened") == 0
  end

  test "reopen rolls back when the audit event cannot be persisted", %{user: owner} do
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment}} =
             Treatments.open_for_order(9_998_043_508, owner.id)

    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)
    assert {:ok, resolved} = Treatments.resolve(assigned, agent)
    previous_inserter = Application.get_env(:chat, :treatment_audit_event_inserter)

    Application.put_env(
      :chat,
      :treatment_audit_event_inserter,
      Chat.TestSupport.FailingTreatmentAuditEventInserter
    )

    on_exit(fn -> restore_env(:treatment_audit_event_inserter, previous_inserter) end)

    assert {:error, %Ecto.Changeset{} = changeset} = Treatments.reopen(resolved, owner)
    assert "forced audit failure" in errors_on(changeset).event_type

    assert %{
             status: "resolved",
             assigned_agent_id: assigned_agent_id,
             assigned_at: assigned_at,
             resolved_by_id: resolved_by_id,
             resolved_at: resolved_at
           } = Repo.get!(Treatment, treatment.id)

    assert assigned_agent_id == resolved.assigned_agent_id
    assert assigned_at == resolved.assigned_at
    assert resolved_by_id == resolved.resolved_by_id
    assert resolved_at == resolved.resolved_at
    assert audit_event_count(treatment, owner, "treatment_reopened") == 0
  end

  test "concurrent reopen allows only the first transition", %{user: owner} do
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment}} =
             Treatments.open_for_order(9_998_043_509, owner.id)

    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)
    assert {:ok, resolved} = Treatments.resolve(assigned, agent)

    tasks =
      for _ <- 1..2 do
        task =
          Task.async(fn ->
            receive do
              :reopen -> Treatments.reopen(resolved, owner)
            end
          end)

        Sandbox.allow(Repo, self(), task.pid)
        task
      end

    Enum.each(tasks, &send(&1.pid, :reopen))

    outcomes =
      tasks
      |> Enum.map(&Task.await(&1, 5_000))
      |> Enum.map(fn
        {:ok, _treatment, :reopened} -> :reopened
        {:error, :invalid_status} -> :invalid_status
      end)
      |> Enum.sort()

    assert [:invalid_status, :reopened] = outcomes
    assert Repo.get!(Treatment, treatment.id).status == "in_progress"
    assert audit_event_count(treatment, owner, "treatment_reopened") == 1
  end

  test "reopening a treatment that no longer exists returns not found", %{user: user} do
    missing_treatment = %Treatment{id: Ecto.UUID.generate()}

    assert {:error, :not_found} = Treatments.reopen(missing_treatment, user)
  end

  test "room resolution reports an effective transition explicitly", %{user: user} do
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_043_497, user.id)

    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)

    assert {:ok, resolved, :resolved} = Treatments.resolve_for_room(room.id, agent)
    assert resolved.id == assigned.id
    assert resolved.status == "resolved"

    assert {:error, :invalid_status} = Treatments.resolve_for_room(room.id, agent)
  end

  test "unauthorized user cannot resolve a treatment", %{user: user} do
    agent = logistics_agent_fixture()
    assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_043_490, user.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)

    assert {:error, :forbidden} = Treatments.resolve(assigned, user)

    assert %{status: "in_progress", resolved_by_id: nil, resolved_at: nil} =
             Repo.get!(Treatment, treatment.id)

    assert audit_event_count(treatment, user, "treatment_resolved") == 0
  end

  test "authorized user who is not assigned cannot resolve a treatment", %{user: user} do
    assigned_agent = logistics_agent_fixture()
    other_agent = logistics_agent_fixture()
    assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_043_491, user.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, assigned_agent)

    assert {:error, :not_assigned_agent} = Treatments.resolve(assigned, other_agent)

    assert %{status: "in_progress", resolved_by_id: nil, resolved_at: nil} =
             Repo.get!(Treatment, treatment.id)

    assert audit_event_count(treatment, user, "treatment_resolved") == 0
  end

  test "open treatment cannot be resolved", %{user: user} do
    agent = logistics_agent_fixture()
    assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_043_492, user.id)

    assert {:error, :invalid_status} = Treatments.resolve(treatment, agent)

    assert %{status: "open", resolved_by_id: nil, resolved_at: nil} =
             Repo.get!(Treatment, treatment.id)

    assert audit_event_count(treatment, user, "treatment_resolved") == 0
  end

  test "resolved treatment cannot be resolved again", %{user: user} do
    agent = logistics_agent_fixture()
    assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_043_493, user.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)
    assert {:ok, resolved} = Treatments.resolve(assigned, agent)

    assert {:error, :invalid_status} = Treatments.resolve(resolved, agent)
    agent_id = agent.id

    assert %{status: "resolved", resolved_by_id: ^agent_id, resolved_at: resolved_at} =
             Repo.get!(Treatment, treatment.id)

    assert resolved_at == resolved.resolved_at
    assert audit_event_count(treatment, user, "treatment_resolved") == 1
  end

  test "closed treatment cannot be resolved", %{user: user} do
    agent = logistics_agent_fixture()
    assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_043_494, user.id)
    assert {:ok, closed} = Treatments.close(treatment, user.id)

    assert {:error, :invalid_status} = Treatments.resolve(closed, agent)

    assert %{status: "closed", resolved_by_id: nil, resolved_at: nil} =
             Repo.get!(Treatment, treatment.id)
  end

  test "resolved agent can be preloaded", %{user: user} do
    agent = logistics_agent_fixture()
    assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_043_495, user.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)
    assert {:ok, resolved} = Treatments.resolve(assigned, agent)

    resolved = Repo.preload(resolved, :resolved_by)

    assert %User{id: resolved_by_id, role: "logistics_agent"} = resolved.resolved_by
    assert resolved_by_id == agent.id
  end

  test "concurrent resolution allows only the first transition", %{user: user} do
    agent = logistics_agent_fixture()
    assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_043_496, user.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)

    tasks =
      for _ <- 1..2 do
        task =
          Task.async(fn ->
            receive do
              :resolve -> Treatments.resolve(assigned, agent)
            end
          end)

        Sandbox.allow(Repo, self(), task.pid)
        task
      end

    Enum.each(tasks, &send(&1.pid, :resolve))

    outcomes =
      tasks
      |> Enum.map(&Task.await(&1, 5_000))
      |> Enum.map(fn
        {:ok, _treatment} -> :ok
        {:error, :invalid_status} -> :invalid_status
      end)
      |> Enum.sort()

    assert [:invalid_status, :ok] = outcomes
    agent_id = agent.id
    assert %{status: "resolved", resolved_by_id: ^agent_id} = Repo.get!(Treatment, treatment.id)
    assert audit_event_count(treatment, user, "treatment_resolved") == 1
  end

  test "commercial user cannot assign a treatment", %{user: user} do
    assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_043_481, user.id)

    assert {:error, :forbidden} = Treatments.assign_agent(treatment, user)
    assert %{assigned_agent_id: nil, assigned_at: nil} = Repo.get!(Treatment, treatment.id)
    assert audit_event_count(treatment, user, "treatment_assigned") == 0
  end

  test "another agent cannot take an assigned treatment", %{user: user} do
    first_agent = logistics_agent_fixture()
    second_agent = logistics_agent_fixture()
    assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_043_482, user.id)

    assert {:ok, assigned} = Treatments.assign_agent(treatment, first_agent)
    assert {:error, :already_assigned} = Treatments.assign_agent(treatment, second_agent)

    first_agent_id = first_agent.id

    assert %{assigned_agent_id: ^first_agent_id, assigned_at: assigned_at} =
             Repo.get!(Treatment, treatment.id)

    assert assigned_at == assigned.assigned_at
    assert audit_event_count(treatment, user, "treatment_assigned") == 1
  end

  test "assigning the same treatment twice by the same agent is idempotent", %{user: user} do
    agent = logistics_agent_fixture()
    assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_043_483, user.id)

    assert {:ok, first} = Treatments.assign_agent(treatment, agent)
    assert {:ok, second} = Treatments.assign_agent(first, agent)

    assert second.assigned_agent_id == agent.id
    assert second.assigned_at == first.assigned_at
    assert second.status == "in_progress"

    agent_id = agent.id

    assert [
             %{event_type: "treatment_assigned", actor_id: ^agent_id},
             %{event_type: "treatment_created"}
           ] =
             Treatments.list_audit_events(treatment.id, user.id)
  end

  test "room assignment rolls back when the audit event cannot be persisted", %{user: user} do
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_043_500, user.id)

    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)

    previous_inserter = Application.get_env(:chat, :treatment_audit_event_inserter)

    Application.put_env(
      :chat,
      :treatment_audit_event_inserter,
      Chat.TestSupport.FailingTreatmentAuditEventInserter
    )

    on_exit(fn -> restore_env(:treatment_audit_event_inserter, previous_inserter) end)

    assert {:error, %Ecto.Changeset{} = changeset} =
             Treatments.assign_agent_for_room(room.id, agent)

    assert "forced audit failure" in errors_on(changeset).event_type

    assert %{status: "open", assigned_agent_id: nil, assigned_at: nil} =
             Repo.get!(Treatment, treatment.id)

    assert audit_event_count(treatment, user, "treatment_assigned") == 0
  end

  test "assignment rolls back the new membership when audit persistence fails", %{user: user} do
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment}} =
             Treatments.open_for_order(9_998_045_005, user.id)

    assert Repo.get_by(Chat.Rooms.RoomMember, user_id: agent.id, room_id: treatment.room_id) ==
             nil

    previous_inserter = Application.get_env(:chat, :treatment_audit_event_inserter)

    Application.put_env(
      :chat,
      :treatment_audit_event_inserter,
      Chat.TestSupport.FailingTreatmentAuditEventInserter
    )

    on_exit(fn -> restore_env(:treatment_audit_event_inserter, previous_inserter) end)

    assert {:error, %Ecto.Changeset{}} = Treatments.assign_agent(treatment, agent)
    assert Repo.get!(Treatment, treatment.id).status == "open"

    assert Repo.get_by(Chat.Rooms.RoomMember, user_id: agent.id, room_id: treatment.room_id) ==
             nil

    assert audit_event_count(treatment, user, "treatment_assigned") == 0
  end

  test "cannot assign a treatment outside the open state", %{user: user} do
    agent = logistics_agent_fixture()
    assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_043_486, user.id)
    assert {:ok, closed_treatment} = Treatments.close(treatment, user.id)

    assert {:error, :invalid_status} = Treatments.assign_agent(closed_treatment, agent)

    assert %{status: "closed", assigned_agent_id: nil, assigned_at: nil} =
             Repo.get!(Treatment, treatment.id)

    assert audit_event_count(treatment, user, "treatment_assigned") == 0
  end

  test "resolved and closed treatments reject assignment", %{user: user} do
    agent = logistics_agent_fixture()

    for {status, order_id} <- [{"resolved", 9_998_043_487}, {"closed", 9_998_043_488}] do
      assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(order_id, user.id)

      assert {:ok, transitioned} =
               treatment
               |> Treatment.changeset(%{status: status})
               |> Repo.update()

      assert {:error, :invalid_status} = Treatments.assign_agent(transitioned, agent)

      assert %{status: ^status, assigned_agent_id: nil, assigned_at: nil} =
               Repo.get!(Treatment, treatment.id)
    end
  end

  test "assigned agent cannot reassign a resolved or closed treatment", %{user: user} do
    agent = logistics_agent_fixture()
    other_agent = logistics_agent_fixture()

    for {status, order_id} <- [{"resolved", 9_998_043_497}, {"closed", 9_998_043_498}] do
      assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(order_id, user.id)
      assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)

      assert {:ok, transitioned} =
               assigned
               |> Treatment.changeset(%{status: status})
               |> Repo.update()

      assert {:error, :invalid_status} = Treatments.assign_agent(transitioned, agent)
      assert {:error, :invalid_status} = Treatments.assign_agent(transitioned, other_agent)
    end
  end

  test "assignment uses the current persisted treatment state", %{user: user} do
    first_agent = logistics_agent_fixture()
    second_agent = logistics_agent_fixture()

    assert {:ok, %{treatment: stale_treatment}} =
             Treatments.open_for_order(9_998_043_484, user.id)

    assert {:ok, _assigned} = Treatments.assign_agent(stale_treatment, first_agent)
    assert {:error, :already_assigned} = Treatments.assign_agent(stale_treatment, second_agent)
  end

  test "concurrent assignment allows only one agent", %{user: user} do
    first_agent = logistics_agent_fixture()
    second_agent = logistics_agent_fixture()
    assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_043_485, user.id)

    tasks =
      for agent <- [first_agent, second_agent] do
        task =
          Task.async(fn ->
            receive do
              :assign -> Treatments.assign_agent(treatment, agent)
            end
          end)

        Sandbox.allow(Repo, self(), task.pid)
        send(task.pid, :assign)
        task
      end

    statuses =
      tasks
      |> Enum.map(&Task.await(&1, 5_000))
      |> Enum.map(fn
        {:ok, _treatment} -> :ok
        {:error, :already_assigned} -> :already_assigned
      end)
      |> Enum.sort()

    assert [:already_assigned, :ok] = statuses
    assert %{assigned_agent_id: assigned_agent_id} = Repo.get!(Treatment, treatment.id)
    assert assigned_agent_id in [first_agent.id, second_agent.id]
    assert audit_event_count(treatment, user, "treatment_assigned") == 1
  end

  test "assigning a treatment that no longer exists returns not found" do
    agent = logistics_agent_fixture()
    missing_treatment = %Treatment{id: Ecto.UUID.generate()}

    assert {:error, :not_found} = Treatments.assign_agent(missing_treatment, agent)
  end

  test "assignment changeset accepts an agent and timestamp", %{user: user} do
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_043_473, user.id)
    assigned_at = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    changeset =
      Treatment.assignment_changeset(treatment, %{
        assigned_agent_id: agent.id,
        assigned_at: assigned_at
      })

    assert changeset.valid?
  end

  test "treatment persists an assigned agent and assignment timestamp", %{user: user} do
    agent = logistics_agent_fixture()
    assigned_at = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_043_474, user.id)

    assert {:ok, updated_treatment} =
             treatment
             |> Treatment.assignment_changeset(%{
               assigned_agent_id: agent.id,
               assigned_at: assigned_at
             })
             |> Repo.update()

    persisted = Repo.get!(Treatment, updated_treatment.id)

    assert persisted.assigned_agent_id == agent.id
    assert persisted.assigned_at == assigned_at
  end

  test "assigned agent can be preloaded from a treatment", %{user: user} do
    agent = logistics_agent_fixture()
    assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_043_475, user.id)

    treatment =
      treatment
      |> Treatment.assignment_changeset(%{
        assigned_agent_id: agent.id,
        assigned_at: DateTime.utc_now()
      })
      |> Repo.update!()
      |> Repo.preload(:assigned_agent)

    agent_id = agent.id
    assert %User{id: ^agent_id, role: "logistics_agent"} = treatment.assigned_agent
  end

  test "assignment rejects a nonexistent agent", %{user: user} do
    assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_043_476, user.id)

    changeset =
      Treatment.assignment_changeset(treatment, %{
        assigned_agent_id: Ecto.UUID.generate(),
        assigned_at: DateTime.utc_now()
      })

    assert {:error, changeset} = Repo.update(changeset)
    assert "does not exist" in errors_on(changeset).assigned_agent_id
  end

  test "deleting an assigned agent nilifies the treatment reference", %{user: user} do
    agent = logistics_agent_fixture()
    assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_043_477, user.id)

    treatment =
      treatment
      |> Treatment.assignment_changeset(%{
        assigned_agent_id: agent.id,
        assigned_at: DateTime.utc_now()
      })
      |> Repo.update!()

    assert {:ok, _deleted_agent} = Repo.delete(agent)
    treatment_id = treatment.id

    assert %{id: ^treatment_id, assigned_agent_id: nil, assigned_at: assigned_at} =
             Repo.get!(Treatment, treatment.id)

    assert assigned_at != nil
  end

  test "regular treatment changeset does not mass assign an assigned agent" do
    changeset =
      Treatment.changeset(%Treatment{}, %{
        order_id: 9_998_043_478,
        assigned_agent_id: Ecto.UUID.generate()
      })

    refute Ecto.Changeset.get_change(changeset, :assigned_agent_id)
  end

  test "reuses the protocol without reopening a closed treatment", %{user: user} do
    assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_043_471, user.id)
    assert {:ok, closed_treatment} = Treatments.close(treatment, user.id)

    assert {:ok, %{treatment: reopened_treatment}} =
             Treatments.open_for_order(9_998_043_471, user.id)

    assert reopened_treatment.id == treatment.id
    assert reopened_treatment.protocol_number == treatment.protocol_number
    assert reopened_treatment.status == "closed"

    assert [
             %{event_type: "treatment_closed"},
             %{event_type: "treatment_created"}
           ] =
             Treatments.list_audit_events(reopened_treatment.id, user.id)

    assert Repo.get!(Chat.Treatments.Treatment, closed_treatment.id).status == "closed"
  end

  test "preload_for_presentation loads assigned agent for presentation", %{user: owner} do
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment}} =
             Treatments.open_for_order(9_998_043_999, owner.id)

    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)
    raw_treatment = Repo.get!(Treatment, assigned.id)

    assert %Ecto.Association.NotLoaded{} = raw_treatment.assigned_agent

    prepared = Treatments.preload_for_presentation(raw_treatment)

    assert %User{id: agent_id, username: agent_username} = prepared.assigned_agent
    assert agent_id == agent.id
    assert agent_username == agent.username

    invalid_input = Enum.find([], &(&1 != nil))

    assert_raise FunctionClauseError, fn ->
      Treatments.preload_for_presentation(invalid_input)
    end
  end

  describe "list_transfer_candidates/2" do
    test "returns eligible logistics agents who are members of the room, excluding the assigned agent",
         %{user: owner} do
      agent_a = logistics_agent_fixture()
      agent_b = logistics_agent_fixture()
      agent_c = logistics_agent_fixture()
      non_member_agent = logistics_agent_fixture()

      assert {:ok, %{treatment: treatment, room: room}} =
               Treatments.open_for_order(9_998_044_101, owner.id)

      assert {:ok, _} = Rooms.join_room(agent_a.id, room.id)
      assert {:ok, _} = Rooms.join_room(agent_b.id, room.id)
      assert {:ok, _} = Rooms.join_room(agent_c.id, room.id)

      assert {:ok, assigned} = Treatments.assign_agent(treatment, agent_a)
      assert assigned.status == "in_progress"

      # Query candidates as agent_a
      assert {:ok, candidates} = Treatments.list_transfer_candidates(room.id, agent_a)

      # Candidates must contain agent_b and agent_c, but NOT agent_a, owner, or non_member_agent
      candidate_ids = Enum.map(candidates, & &1.id)
      assert agent_b.id in candidate_ids
      assert agent_c.id in candidate_ids
      refute agent_a.id in candidate_ids
      refute owner.id in candidate_ids
      refute non_member_agent.id in candidate_ids

      # Projection check: only id and username
      for candidate <- candidates do
        assert Map.keys(candidate) |> Enum.sort() == [:id, :username]
      end

      # Stable ordering by username asc
      usernames = Enum.map(candidates, & &1.username)
      assert usernames == Enum.sort(usernames)
    end

    test "returns eligible logistics agents regardless of Presence (offline agents included)",
         %{user: owner} do
      agent_a = logistics_agent_fixture()
      agent_b = logistics_agent_fixture()

      assert {:ok, %{treatment: treatment, room: room}} =
               Treatments.open_for_order(9_998_044_102, owner.id)

      assert {:ok, _} = Rooms.join_room(agent_a.id, room.id)
      assert {:ok, _} = Rooms.join_room(agent_b.id, room.id)
      assert {:ok, _} = Treatments.assign_agent(treatment, agent_a)

      assert {:ok, candidates} = Treatments.list_transfer_candidates(room.id, agent_a)
      assert Enum.any?(candidates, &(&1.id == agent_b.id))
    end

    test "returns {:error, :not_assigned_agent} when another logistics agent attempts to list candidates",
         %{user: owner} do
      agent_a = logistics_agent_fixture()
      agent_b = logistics_agent_fixture()

      assert {:ok, %{treatment: treatment, room: room}} =
               Treatments.open_for_order(9_998_044_103, owner.id)

      assert {:ok, _} = Rooms.join_room(agent_a.id, room.id)
      assert {:ok, _} = Rooms.join_room(agent_b.id, room.id)
      assert {:ok, _} = Treatments.assign_agent(treatment, agent_a)

      # agent_b is a member and a logistics agent, but not the assigned agent
      assert {:error, :not_assigned_agent} =
               Treatments.list_transfer_candidates(room.id, agent_b)
    end

    test "returns {:error, :invalid_status} when treatment is not in_progress",
         %{user: owner} do
      agent_a = logistics_agent_fixture()

      assert {:ok, %{treatment: treatment, room: room}} =
               Treatments.open_for_order(9_998_044_104, owner.id)

      assert {:ok, _} = Rooms.join_room(agent_a.id, room.id)

      # Status is "open" (unassigned)
      assert {:error, :invalid_status} =
               Treatments.list_transfer_candidates(room.id, agent_a)

      # Assign and resolve
      assert {:ok, assigned} = Treatments.assign_agent(treatment, agent_a)
      assert {:ok, _resolved} = Treatments.resolve(assigned, agent_a)

      # Status is "resolved"
      assert {:error, :invalid_status} =
               Treatments.list_transfer_candidates(room.id, agent_a)
    end

    test "returns {:error, :forbidden} when caller lacks treatment.transfer permission",
         %{user: commercial} do
      agent_a = logistics_agent_fixture()

      assert {:ok, %{treatment: treatment, room: room}} =
               Treatments.open_for_order(9_998_044_105, commercial.id)

      assert {:ok, _} = Rooms.join_room(agent_a.id, room.id)
      assert {:ok, _} = Treatments.assign_agent(treatment, agent_a)

      # Commercial user lacks "treatment.transfer" permission
      assert {:error, :forbidden} =
               Treatments.list_transfer_candidates(room.id, commercial)
    end

    test "returns {:error, :forbidden} when caller is not a member of the room",
         %{user: owner} do
      agent_a = logistics_agent_fixture()
      outsider_agent = logistics_agent_fixture()

      assert {:ok, %{treatment: treatment, room: room}} =
               Treatments.open_for_order(9_998_044_106, owner.id)

      assert {:ok, _} = Rooms.join_room(agent_a.id, room.id)
      assert {:ok, _} = Treatments.assign_agent(treatment, agent_a)

      assert {:error, :forbidden} =
               Treatments.list_transfer_candidates(room.id, outsider_agent)
    end

    test "returns {:error, :not_found} for unknown room or invalid UUID",
         %{user: _owner} do
      agent = logistics_agent_fixture()
      non_existent_room_id = Ecto.UUID.generate()

      assert {:error, :not_found} =
               Treatments.list_transfer_candidates(non_existent_room_id, agent)

      assert {:error, :invalid_id} =
               Treatments.list_transfer_candidates("not-a-uuid", agent)
    end

    test "is a pure read query and does not produce mutations, audit events or status changes",
         %{user: owner} do
      agent_a = logistics_agent_fixture()
      agent_b = logistics_agent_fixture()

      assert {:ok, %{treatment: treatment, room: room}} =
               Treatments.open_for_order(9_998_044_107, owner.id)

      assert {:ok, _} = Rooms.join_room(agent_a.id, room.id)
      assert {:ok, _} = Rooms.join_room(agent_b.id, room.id)
      assert {:ok, assigned} = Treatments.assign_agent(treatment, agent_a)

      audit_events_before = Treatments.list_audit_events(treatment.id, owner.id)

      assert {:ok, candidates} = Treatments.list_transfer_candidates(room.id, agent_a)
      assert length(candidates) == 1

      treatment_after = Repo.get!(Treatment, treatment.id)
      assert treatment_after.status == assigned.status
      assert treatment_after.assigned_agent_id == assigned.assigned_agent_id
      assert treatment_after.assigned_at == assigned.assigned_at
      assert treatment_after.resolved_by_id == nil
      assert treatment_after.resolved_at == nil

      audit_events_after = Treatments.list_audit_events(treatment.id, owner.id)
      assert length(audit_events_after) == length(audit_events_before)
    end

    test "executes a constant number of queries and avoids N+1 regardless of candidate count",
         %{user: owner} do
      agent_a = logistics_agent_fixture()
      agents = for _ <- 1..5, do: logistics_agent_fixture()

      assert {:ok, %{treatment: treatment, room: room}} =
               Treatments.open_for_order(9_998_044_108, owner.id)

      assert {:ok, _} = Rooms.join_room(agent_a.id, room.id)
      for agent <- agents, do: assert({:ok, _} = Rooms.join_room(agent.id, room.id))

      assert {:ok, _} = Treatments.assign_agent(treatment, agent_a)

      handler_id = "transfer-candidates-query-counter-#{System.unique_integer([:positive])}"
      test_pid = self()

      :ok =
        :telemetry.attach(
          handler_id,
          [:chat, :repo, :query],
          fn _event, _measurements, metadata, _config ->
            send(test_pid, {:query, metadata.query})
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert {:ok, candidates} = Treatments.list_transfer_candidates(room.id, agent_a)
      assert length(candidates) == 5

      queries =
        Stream.repeatedly(fn ->
          receive do
            {:query, query} -> query
          after
            0 -> nil
          end
        end)
        |> Enum.take_while(&(&1 != nil))

      # Verifies constant O(1) query execution (no query executed per candidate)
      assert length(queries) <= 4
    end

    test "revalidates candidate eligibility upon mutation when candidate leaves room after listing",
         %{user: owner} do
      agent_a = logistics_agent_fixture()
      agent_b = logistics_agent_fixture()

      assert {:ok, %{treatment: treatment, room: room}} =
               Treatments.open_for_order(9_998_044_109, owner.id)

      assert {:ok, _} = Rooms.join_room(agent_a.id, room.id)
      assert {:ok, _} = Rooms.join_room(agent_b.id, room.id)
      assert {:ok, _assigned} = Treatments.assign_agent(treatment, agent_a)

      # 1. Discovery: agent_b is present in the list of eligible candidates
      assert {:ok, candidates} = Treatments.list_transfer_candidates(room.id, agent_a)
      assert Enum.any?(candidates, &(&1.id == agent_b.id))

      # 2. Race condition: agent_b leaves the room after discovery but before mutation
      assert {:ok, _} = Rooms.leave_room(agent_b.id, room.id)

      # 3. Mutation: transfer_agent_for_room grants historical target access
      assert {:ok, transferred, :transferred} =
               Treatments.transfer_agent_for_room(room.id, agent_a, agent_b.id)

      assert transferred.assigned_agent_id == agent_b.id
      assert Rooms.room_member?(agent_b.id, room.id)

      # Invariant: Treatment ownership moves to the revalidated target
      persisted = Repo.get!(Treatment, treatment.id)
      assert persisted.assigned_agent_id == agent_b.id
      assert persisted.status == "in_progress"
    end

    test "all returned candidates strictly satisfy fundamental target criteria of transfer_agent_for_room/3",
         %{user: owner} do
      agent_a = logistics_agent_fixture()
      agent_b = logistics_agent_fixture()
      agent_c = logistics_agent_fixture()

      assert {:ok, %{treatment: treatment, room: room}} =
               Treatments.open_for_order(9_998_044_110, owner.id)

      assert {:ok, _} = Rooms.join_room(agent_a.id, room.id)
      assert {:ok, _} = Rooms.join_room(agent_b.id, room.id)
      assert {:ok, _} = Rooms.join_room(agent_c.id, room.id)
      assert {:ok, _assigned} = Treatments.assign_agent(treatment, agent_a)

      assert {:ok, candidates} = Treatments.list_transfer_candidates(room.id, agent_a)
      assert length(candidates) == 2

      # Every candidate in the list must satisfy all target criteria:
      for candidate <- candidates do
        user = Repo.get!(User, candidate.id)
        assert user.role == "logistics_agent"
        assert user.id != agent_a.id
        assert user.id != treatment.assigned_agent_id
        assert {:ok, _} = Rooms.fetch_member_room(user.id, room.id)
      end

      # Furthermore, transfer to any returned candidate succeeds in transfer_agent_for_room
      target = hd(candidates)

      assert {:ok, transferred, :transferred} =
               Treatments.transfer_agent_for_room(room.id, agent_a, target.id)

      assert transferred.assigned_agent_id == target.id
      assert transferred.status == "in_progress"
    end
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

  defp audit_event_count(treatment, user, event_type) do
    treatment.id
    |> Treatments.list_audit_events(user.id)
    |> Enum.count(&(&1.event_type == event_type))
  end

  defp audit_event_counts(treatment, user, event_types) do
    treatment.id
    |> Treatments.list_audit_events(user.id)
    |> Enum.filter(&(&1.event_type in event_types))
    |> Enum.frequencies_by(& &1.event_type)
    |> Map.merge(Map.new(event_types, &{&1, 0}), fn _key, existing, _default -> existing end)
  end

  defp restore_env(key, nil), do: Application.delete_env(:chat, key)
  defp restore_env(key, value), do: Application.put_env(:chat, key, value)
end
