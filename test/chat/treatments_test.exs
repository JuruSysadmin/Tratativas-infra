defmodule Chat.TreatmentsTest do
  use Chat.DataCase, async: false

  alias Chat.Accounts.User
  alias Chat.Auth.Identity
  alias Chat.Repo
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

  test "logistics agent can assign an available treatment", %{user: user} do
    agent = logistics_agent_fixture()
    assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_043_480, user.id)

    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)

    assert assigned.assigned_agent_id == agent.id
    assert assigned.assigned_at != nil
  end

  test "commercial user cannot assign a treatment", %{user: user} do
    assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_043_481, user.id)

    assert {:error, :forbidden} = Treatments.assign_agent(treatment, user)
    assert %{assigned_agent_id: nil, assigned_at: nil} = Repo.get!(Treatment, treatment.id)
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
  end

  test "assigning the same treatment twice by the same agent is idempotent", %{user: user} do
    agent = logistics_agent_fixture()
    assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_043_483, user.id)

    assert {:ok, first} = Treatments.assign_agent(treatment, agent)
    assert {:ok, second} = Treatments.assign_agent(first, agent)

    assert second.assigned_agent_id == agent.id
    assert second.assigned_at == first.assigned_at
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
end
