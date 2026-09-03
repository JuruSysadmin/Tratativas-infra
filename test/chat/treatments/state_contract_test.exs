defmodule Chat.Treatments.StateContractTest do
  use Chat.DataCase, async: false

  alias Chat.Accounts.User
  alias Chat.Auth.Identity
  alias Chat.Repo
  alias Chat.Rooms
  alias Chat.Treatments
  alias Chat.Treatments.Treatment

  describe "State Machine Contract: Valid Transitions" do
    test "open -> in_progress via assign_agent by logistics agent" do
      ctx = setup_fixture(:open)
      agent = logistics_agent_fixture()
      assert {:ok, _membership} = Rooms.join_room(agent.id, ctx.room.id)

      assert {:ok, assigned} = Treatments.assign_agent(ctx.treatment, agent)
      assert assigned.status == "in_progress"
      assert assigned.assigned_agent_id == agent.id
      assert assigned.assigned_at != nil
      assert Repo.get!(Treatment, ctx.treatment.id).status == "in_progress"
    end

    test "in_progress -> open via unassign by assigned logistics agent" do
      ctx = setup_fixture(:in_progress)

      assert {:ok, unassigned, :unassigned} = Treatments.unassign(ctx.treatment, ctx.agent)
      assert unassigned.status == "open"
      assert unassigned.assigned_agent_id == nil
      assert unassigned.assigned_at == nil
      assert Repo.get!(Treatment, ctx.treatment.id).status == "open"
    end

    test "in_progress -> in_progress via transfer_agent to another logistics agent in room" do
      ctx = setup_fixture(:in_progress)
      target_agent = logistics_agent_fixture()
      assert {:ok, _membership} = Rooms.join_room(target_agent.id, ctx.room.id)

      assert {:ok, transferred, :transferred} =
               Treatments.transfer_agent(ctx.treatment, ctx.agent, target_agent)

      assert transferred.status == "in_progress"
      assert transferred.assigned_agent_id == target_agent.id
      assert Repo.get!(Treatment, ctx.treatment.id).assigned_agent_id == target_agent.id
    end

    test "in_progress -> pending_confirmation via resolve by assigned logistics agent" do
      ctx = setup_fixture(:in_progress)

      assert {:ok, resolved} = Treatments.resolve(ctx.treatment, ctx.agent)
      assert resolved.status == "pending_confirmation"
      assert resolved.resolved_by_id == ctx.agent.id
      assert resolved.resolved_at != nil
      assert Repo.get!(Treatment, ctx.treatment.id).status == "pending_confirmation"
    end

    test "in_progress -> closed via close by assigned logistics agent (direct closure)" do
      ctx = setup_fixture(:in_progress)

      assert {:ok, closed, :closed} = Treatments.close(ctx.treatment, ctx.agent)
      assert closed.status == "closed"
      assert closed.closed_by_id == ctx.agent.id
      assert closed.closed_at != nil
      assert Repo.get!(Treatment, ctx.treatment.id).status == "closed"
    end

    test "resolved -> closed via confirm_resolution by commercial room member" do
      ctx = setup_fixture(:resolved)

      assert {:ok, closed, :closed} = Treatments.confirm_resolution(ctx.treatment, ctx.owner)
      assert closed.status == "closed"
      assert closed.closed_by_id == ctx.owner.id
      assert closed.closed_at != nil
      assert Repo.get!(Treatment, ctx.treatment.id).status == "closed"
    end

    test "resolved -> in_progress via reopen by commercial owner" do
      ctx = setup_fixture(:resolved)

      assert {:ok, reopened, :reopened} = Treatments.reopen(ctx.treatment, ctx.owner)
      assert reopened.status == "in_progress"
      assert reopened.resolved_by_id == nil
      assert reopened.resolved_at == nil
      assert Repo.get!(Treatment, ctx.treatment.id).status == "in_progress"
    end

    test "closed -> in_progress via reopen by commercial owner" do
      ctx = setup_fixture(:closed)

      assert {:ok, reopened, :reopened} = Treatments.reopen(ctx.treatment, ctx.owner)
      assert reopened.status == "in_progress"
      assert Repo.get!(Treatment, ctx.treatment.id).status == "in_progress"
    end

    test "resolved -> in_progress via reopen by assigned logistics agent" do
      ctx = setup_fixture(:resolved)

      assert {:ok, reopened, :reopened} = Treatments.reopen(ctx.treatment, ctx.agent)
      assert reopened.status == "in_progress"
      assert Repo.get!(Treatment, ctx.treatment.id).status == "in_progress"
    end

    test "closed -> in_progress via reopen by assigned logistics agent" do
      ctx = setup_fixture(:closed)

      assert {:ok, reopened, :reopened} = Treatments.reopen(ctx.treatment, ctx.agent)
      assert reopened.status == "in_progress"
      assert Repo.get!(Treatment, ctx.treatment.id).status == "in_progress"
    end
  end

  describe "State Machine Contract: Prohibited Initial States" do
    test "assign_agent is prohibited on in_progress, resolved and closed" do
      other_agent = logistics_agent_fixture()

      for state <- [:in_progress, :resolved, :closed] do
        ctx = setup_fixture(state)
        assert {:ok, _} = Rooms.join_room(other_agent.id, ctx.room.id)

        assert {:error, reason} = Treatments.assign_agent(ctx.treatment, other_agent)
        assert reason in [:already_assigned, :invalid_status]
      end
    end

    test "unassign is prohibited on open, resolved and closed" do
      for state <- [:open, :resolved, :closed] do
        ctx = setup_fixture(state)
        agent = ctx[:agent] || logistics_agent_fixture()
        if is_nil(ctx[:agent]), do: {:ok, _} = Rooms.join_room(agent.id, ctx.room.id)

        assert {:error, :invalid_status} = Treatments.unassign(ctx.treatment, agent)
      end
    end

    test "transfer_agent is prohibited on open, resolved and closed" do
      target_agent = logistics_agent_fixture()

      for state <- [:open, :resolved, :closed] do
        ctx = setup_fixture(state)
        agent = ctx[:agent] || logistics_agent_fixture()
        if is_nil(ctx[:agent]), do: {:ok, _} = Rooms.join_room(agent.id, ctx.room.id)
        assert {:ok, _} = Rooms.join_room(target_agent.id, ctx.room.id)

        assert {:error, :invalid_status} =
                 Treatments.transfer_agent(ctx.treatment, agent, target_agent)
      end
    end

    test "resolve is prohibited on open, resolved and closed" do
      for state <- [:open, :resolved, :closed] do
        ctx = setup_fixture(state)
        agent = ctx[:agent] || logistics_agent_fixture()
        if is_nil(ctx[:agent]), do: {:ok, _} = Rooms.join_room(agent.id, ctx.room.id)

        assert {:error, :invalid_status} = Treatments.resolve(ctx.treatment, agent)
      end
    end

    test "close is prohibited on open, resolved and closed" do
      for state <- [:open, :resolved, :closed] do
        ctx = setup_fixture(state)
        agent = ctx[:agent] || logistics_agent_fixture()
        if is_nil(ctx[:agent]), do: {:ok, _} = Rooms.join_room(agent.id, ctx.room.id)

        assert {:error, :invalid_status} = Treatments.close(ctx.treatment, agent)
      end
    end

    test "confirm_resolution is prohibited on open, in_progress and closed" do
      for state <- [:open, :in_progress, :closed] do
        ctx = setup_fixture(state)

        assert {:error, :invalid_status} =
                 Treatments.confirm_resolution(ctx.treatment, ctx.owner)
      end
    end

    test "reopen is prohibited on open and in_progress" do
      for state <- [:open, :in_progress] do
        ctx = setup_fixture(state)

        assert {:error, :invalid_status} = Treatments.reopen(ctx.treatment, ctx.owner)
      end
    end
  end

  describe "State Machine Contract: Role and Capability Enforcement" do
    test "commercial user is forbidden from executing logistics-only operations" do
      ctx = setup_fixture(:in_progress)
      target_agent = logistics_agent_fixture()
      assert {:ok, _} = Rooms.join_room(target_agent.id, ctx.room.id)

      assert {:error, :forbidden} = Treatments.assign_agent(ctx.treatment, ctx.owner)
      assert {:error, :forbidden} = Treatments.unassign(ctx.treatment, ctx.owner)

      assert {:error, :forbidden} =
               Treatments.transfer_agent(ctx.treatment, ctx.owner, target_agent)

      assert {:error, :forbidden} = Treatments.resolve(ctx.treatment, ctx.owner)
      assert {:error, :forbidden} = Treatments.close(ctx.treatment, ctx.owner)
    end

    test "logistics agent is forbidden from executing commercial-only confirmation" do
      ctx = setup_fixture(:resolved)

      assert {:error, :forbidden} = Treatments.confirm_resolution(ctx.treatment, ctx.agent)
    end
  end

  describe "State Machine Contract: Assignment and Membership Guardrails" do
    test "unassigned logistics agent cannot unassign, transfer, resolve, close, or reopen" do
      ctx = setup_fixture(:in_progress)
      other_agent = logistics_agent_fixture()
      assert {:ok, _} = Rooms.join_room(other_agent.id, ctx.room.id)
      target_agent = logistics_agent_fixture()
      assert {:ok, _} = Rooms.join_room(target_agent.id, ctx.room.id)

      assert {:error, :not_assigned_agent} = Treatments.unassign(ctx.treatment, other_agent)

      assert {:error, :not_assigned_agent} =
               Treatments.transfer_agent(ctx.treatment, other_agent, target_agent)

      assert {:error, :not_assigned_agent} = Treatments.resolve(ctx.treatment, other_agent)
      assert {:error, :not_assigned_agent} = Treatments.close(ctx.treatment, other_agent)

      ctx_resolved = setup_fixture(:resolved)
      assert {:ok, _} = Rooms.join_room(other_agent.id, ctx_resolved.room.id)

      assert {:error, :not_assigned_agent} =
               Treatments.reopen(ctx_resolved.treatment, other_agent)
    end

    test "room outsider receives not_found on operations requiring room membership" do
      {:ok, outsider_commercial} =
        Identity.sync_user(
          %{"sub" => "state-contract-outsider-comm-#{System.unique_integer([:positive])}"},
          %{}
        )

      outsider_agent = logistics_agent_fixture()

      ctx_resolved = setup_fixture(:resolved)

      assert {:error, :not_found} =
               Treatments.confirm_resolution(ctx_resolved.treatment, outsider_commercial)

      ctx_in_progress = setup_fixture(:in_progress)

      assert {:error, :not_found} =
               Treatments.close(ctx_in_progress.treatment, outsider_agent)
    end
  end

  # =========================================================================
  # Setup Fixtures
  # =========================================================================

  defp setup_fixture(:open) do
    order_id = System.unique_integer([:positive])
    {:ok, owner} = Identity.sync_user(%{"sub" => "state-contract-owner-#{order_id}"}, %{})

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(order_id, owner.id)

    %{treatment: treatment, room: room, owner: owner}
  end

  defp setup_fixture(:in_progress) do
    ctx = setup_fixture(:open)
    agent = logistics_agent_fixture()
    assert {:ok, _membership} = Rooms.join_room(agent.id, ctx.room.id)
    assert {:ok, assigned} = Treatments.assign_agent(ctx.treatment, agent)
    Map.merge(ctx, %{treatment: assigned, agent: agent})
  end

  defp setup_fixture(:resolved) do
    ctx = setup_fixture(:in_progress)
    assert {:ok, resolved} = Treatments.resolve(ctx.treatment, ctx.agent)
    Map.put(ctx, :treatment, resolved)
  end

  defp setup_fixture(:closed) do
    ctx = setup_fixture(:in_progress)
    assert {:ok, closed, :closed} = Treatments.close(ctx.treatment, ctx.agent)
    Map.put(ctx, :treatment, closed)
  end

  defp logistics_agent_fixture do
    %User{}
    |> User.auth_changeset(%{
      email: "state-contract-agent-#{System.unique_integer([:positive])}@example.com",
      username: "state-contract-agent-#{System.unique_integer([:positive])}",
      role: "logistics_agent"
    })
    |> Repo.insert!()
  end
end
