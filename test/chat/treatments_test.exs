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

  test "treatment can exist without an assigned agent", %{user: user} do
    assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_043_472, user.id)

    assert treatment.assigned_agent_id == nil
    assert treatment.assigned_at == nil
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

    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)

    assert assigned.assigned_agent_id == agent.id
    assert assigned.assigned_at != nil
    assert assigned.status == "in_progress"

    assert Repo.get!(Treatment, treatment.id).status == "in_progress"

    agent_id = agent.id

    assert [
             %{event_type: "treatment_assigned", actor_id: ^agent_id},
             %{event_type: "treatment_created", actor_id: _owner_id}
           ] =
             Treatments.list_audit_events(treatment.id, user.id)
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

    assert {:ok, %{treatment: treatment}} =
             Treatments.open_for_order(9_998_043_502, owner.id)

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

  test "reuses the protocol and audits a closed treatment reopening", %{user: user} do
    assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_043_471, user.id)
    assert {:ok, closed_treatment} = Treatments.close(treatment, user.id)

    assert {:ok, %{treatment: reopened_treatment}} =
             Treatments.open_for_order(9_998_043_471, user.id)

    assert reopened_treatment.id == treatment.id
    assert reopened_treatment.protocol_number == treatment.protocol_number
    assert reopened_treatment.status == "open"

    assert [
             %{event_type: "treatment_reopened"},
             %{event_type: "treatment_closed"},
             %{event_type: "treatment_created"}
           ] =
             Treatments.list_audit_events(reopened_treatment.id, user.id)

    assert Repo.get!(Chat.Treatments.Treatment, closed_treatment.id).status == "open"
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

  defp restore_env(key, nil), do: Application.delete_env(:chat, key)
  defp restore_env(key, value), do: Application.put_env(:chat, key, value)
end
