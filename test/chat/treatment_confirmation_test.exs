defmodule Chat.TreatmentConfirmationTest do
  use Chat.DataCase, async: false

  alias Chat.Accounts.User
  alias Chat.Auth.Identity
  alias Chat.Repo
  alias Chat.Rooms
  alias Chat.Treatments
  alias Chat.Treatments.Treatment
  alias Ecto.Adapters.SQL.Sandbox

  test "a commercial room member confirms a resolved treatment exactly once" do
    {:ok, commercial} = Identity.sync_user(%{"sub" => "confirmation-commercial"}, %{})
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_046_001, commercial.id)

    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)
    assert {:ok, resolved} = Treatments.resolve(assigned, agent)

    assert {:ok, closed, :closed} = Treatments.confirm_resolution(resolved, commercial)
    assert closed.status == "closed"
    assert closed.closed_by_id == commercial.id
    assert closed.closed_at != nil
    assert closed.resolved_by_id == agent.id
    assert closed.resolved_at == resolved.resolved_at

    assert %{status: "closed", closed_by_id: closed_by_id, closed_at: closed_at} =
             Repo.get!(Treatment, treatment.id)

    assert closed_by_id == commercial.id
    assert closed_at == closed.closed_at
    assert event_count(treatment, commercial, "treatment_closed") == 1
  end

  test "confirmation rejects non-commercials, non-members and non-resolved states without an audit" do
    {:ok, commercial} = Identity.sync_user(%{"sub" => "confirmation-owner"}, %{})
    {:ok, outsider} = Identity.sync_user(%{"sub" => "confirmation-outsider"}, %{})
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_046_002, commercial.id)

    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)
    assert {:error, :invalid_status} = Treatments.confirm_resolution(assigned, commercial)
    assert {:ok, resolved} = Treatments.resolve(assigned, agent)

    assert {:error, :forbidden} = Treatments.confirm_resolution(resolved, agent)
    assert {:error, :not_found} = Treatments.confirm_resolution(resolved, outsider)
    assert event_count(treatment, commercial, "treatment_closed") == 0
  end

  test "concurrent confirmations create one closure audit event" do
    {:ok, commercial} = Identity.sync_user(%{"sub" => "confirmation-concurrent"}, %{})
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_046_003, commercial.id)

    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)
    assert {:ok, resolved} = Treatments.resolve(assigned, agent)

    tasks =
      for _ <- 1..2 do
        task =
          Task.async(fn ->
            receive do
              :confirm -> Treatments.confirm_resolution(resolved, commercial)
            end
          end)

        Sandbox.allow(Repo, self(), task.pid)
        task
      end

    Enum.each(tasks, &send(&1.pid, :confirm))

    assert [:closed, :invalid_status] =
             tasks
             |> Enum.map(&Task.await(&1, 5_000))
             |> Enum.map(fn
               {:ok, _treatment, :closed} -> :closed
               {:error, :invalid_status} -> :invalid_status
             end)
             |> Enum.sort()

    assert event_count(treatment, commercial, "treatment_closed") == 1
  end

  defp logistics_agent_fixture do
    %User{}
    |> User.auth_changeset(%{
      email: "confirmation-agent-#{System.unique_integer([:positive])}@example.com",
      username: "confirmation-agent-#{System.unique_integer([:positive])}",
      role: "logistics_agent"
    })
    |> Repo.insert!()
  end

  defp event_count(treatment, user, event_type) do
    treatment.id
    |> Treatments.list_audit_events(user.id)
    |> Enum.count(&(&1.event_type == event_type))
  end
end
