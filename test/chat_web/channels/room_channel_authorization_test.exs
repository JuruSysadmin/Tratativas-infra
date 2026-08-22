defmodule ChatWeb.RoomChannelAuthorizationTest do
  use Chat.DataCase, async: true

  import Phoenix.ChannelTest

  alias Chat.Accounts.User
  alias Chat.Auth.Identity
  alias Chat.Messages
  alias Chat.Messages.{Attachments, MessageAttachment}
  alias Chat.Repo
  alias Chat.Rooms
  alias Chat.Treatments
  alias Chat.Treatments.Treatment
  alias ChatWeb.RoomChannel
  alias ChatWeb.UserSocket

  @endpoint ChatWeb.Endpoint

  test "logistics agent can assign the room treatment through the channel" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-treatment-owner"}, %{})
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_000, owner.id)

    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-treatment-agent", %{current_user: agent})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref = push(socket, "treatment:assign_to_me", %{})

    assert_reply ref, :ok, %{
      treatment_id: treatment_id,
      assigned_agent_id: assigned_agent_id,
      assigned_at: assigned_at
    }

    assert treatment_id == treatment.id
    assert assigned_agent_id == agent.id
    assert assigned_at != nil

    assert_push "treatment:agent_assigned", %{
      treatment_id: ^treatment_id,
      assigned_agent_id: ^assigned_agent_id,
      assigned_at: ^assigned_at
    }

    agent_id = agent.id

    assert %{
             assigned_agent_id: ^agent_id,
             assigned_at: persisted_assigned_at,
             status: "in_progress"
           } =
             Repo.get!(Treatment, treatment.id)

    assert persisted_assigned_at == assigned_at
  end

  test "assigned logistics agent can unassign the room treatment through the channel" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-unassign-owner"}, %{})
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_017, owner.id)

    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-unassign-agent", %{current_user: agent})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref = push(socket, "treatment:unassign", %{})

    assert_reply ref, :ok, %{
      treatment_id: treatment_id,
      status: "open",
      assigned_agent_id: nil,
      assigned_at: nil
    }

    assert treatment_id == treatment.id
    assert Repo.get!(Treatment, treatment.id).status == "open"
    assert assigned.assigned_agent_id == agent.id

    assert_push "treatment:unassigned", %{
      treatment_id: ^treatment_id,
      status: "open",
      assigned_agent_id: nil,
      assigned_at: nil
    }
  end

  test "commercial member receives forbidden when unassigning through the channel" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-unassign-commercial"}, %{})
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_018, owner.id)

    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
    assert {:ok, _assigned} = Treatments.assign_agent(treatment, agent)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-unassign-commercial", %{current_user: owner})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref = push(socket, "treatment:unassign", %{})

    assert_reply ref, :error, %{reason: "forbidden"}
    refute_push "treatment:unassigned", _payload
  end

  test "unassign ignores client ownership fields and uses the authenticated agent" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-unassign-payload"}, %{})
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_019, owner.id)

    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
    assert {:ok, _assigned} = Treatments.assign_agent(treatment, agent)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-unassign-payload", %{current_user: agent})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref = push(socket, "treatment:unassign", %{"assigned_agent_id" => Ecto.UUID.generate()})

    assert_reply ref, :ok, %{status: "open", assigned_agent_id: nil, assigned_at: nil}
    assert_push "treatment:unassigned", _payload
  end

  test "assigned logistics agent can resolve the room treatment through the channel" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-resolution-owner"}, %{})
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_006, owner.id)

    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-resolution-agent", %{current_user: agent})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref = push(socket, "treatment:resolve", %{})

    assert_reply ref, :ok, %{
      treatment_id: treatment_id,
      status: "resolved",
      resolved_by_id: resolved_by_id,
      resolved_at: resolved_at
    }

    assert treatment_id == treatment.id
    assert resolved_by_id == agent.id
    assert resolved_at != nil

    agent_id = agent.id

    assert %{
             status: "resolved",
             resolved_by_id: ^agent_id,
             resolved_at: ^resolved_at,
             assigned_agent_id: ^agent_id,
             assigned_at: assigned_at
           } = Repo.get!(Treatment, treatment.id)

    assert assigned_at == assigned.assigned_at

    assert_push "treatment:resolved", %{
      treatment_id: ^treatment_id,
      status: "resolved",
      resolved_by_id: ^resolved_by_id,
      resolved_at: ^resolved_at
    }

    retry_ref = push(socket, "treatment:resolve", %{})
    assert_reply retry_ref, :error, %{reason: "invalid_status"}
    refute_push "treatment:resolved", _duplicate

    assert resolution_audit_count(treatment, agent) == 1
  end

  test "assigned logistics agent can transfer the room treatment through the channel" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-transfer-owner"}, %{})
    current_agent = logistics_agent_fixture()
    target_agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_007, owner.id)

    assert {:ok, _membership} = Rooms.join_room(current_agent.id, room.id)
    assert {:ok, _membership} = Rooms.join_room(target_agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, current_agent)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-transfer-agent", %{current_user: current_agent})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref = push(socket, "treatment:transfer", %{"target_agent_id" => target_agent.id})

    assert_reply ref, :ok, %{
      treatment_id: treatment_id,
      status: "in_progress",
      assigned_agent_id: assigned_agent_id,
      assigned_at: assigned_at
    }

    assert treatment_id == treatment.id
    assert assigned_agent_id == target_agent.id
    assert assigned_at != assigned.assigned_at
    assert transfer_audit_count(treatment, current_agent) == 1

    assert_push "treatment:transferred", %{
      treatment_id: ^treatment_id,
      status: "in_progress",
      assigned_agent_id: ^assigned_agent_id,
      assigned_at: ^assigned_at
    }
  end

  test "transferred treatment reaches every room subscriber from one transition" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-transfer-broadcast-owner"}, %{})
    current_agent = logistics_agent_fixture()
    target_agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_016, owner.id)

    for agent <- [current_agent, target_agent] do
      assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
    end

    assert {:ok, _assigned} = Treatments.assign_agent(treatment, current_agent)

    {:ok, _reply, current_socket} =
      UserSocket
      |> socket("channel-transfer-broadcast-current", %{current_user: current_agent})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    {:ok, _reply, _target_socket} =
      UserSocket
      |> socket("channel-transfer-broadcast-target", %{current_user: target_agent})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref = push(current_socket, "treatment:transfer", %{"target_agent_id" => target_agent.id})

    assert_reply ref, :ok, %{treatment_id: treatment_id, assigned_agent_id: target_agent_id}
    assert target_agent_id == target_agent.id

    assert_push "treatment:transferred", %{
      treatment_id: ^treatment_id,
      assigned_agent_id: ^target_agent_id
    }

    assert_push "treatment:transferred", %{
      treatment_id: ^treatment_id,
      assigned_agent_id: ^target_agent_id
    }

    refute_push "treatment:transferred", _duplicate
    assert transfer_audit_count(treatment, current_agent) == 1
  end

  test "commercial member receives forbidden when transferring through the channel" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-transfer-commercial"}, %{})
    current_agent = logistics_agent_fixture()
    target_agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_008, owner.id)

    assert {:ok, _membership} = Rooms.join_room(current_agent.id, room.id)
    assert {:ok, _membership} = Rooms.join_room(target_agent.id, room.id)
    assert {:ok, _assigned} = Treatments.assign_agent(treatment, current_agent)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-transfer-commercial", %{current_user: owner})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref = push(socket, "treatment:transfer", %{"target_agent_id" => target_agent.id})

    assert_reply ref, :error, %{reason: "forbidden"}
    refute_push "treatment:transferred", _payload
    assert transfer_audit_count(treatment, owner) == 0
  end

  test "non-owner logistics agent receives not_assigned_agent" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-transfer-owner-error"}, %{})
    current_agent = logistics_agent_fixture()
    other_agent = logistics_agent_fixture()
    target_agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_009, owner.id)

    for agent <- [current_agent, other_agent, target_agent] do
      assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
    end

    assert {:ok, _assigned} = Treatments.assign_agent(treatment, current_agent)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-transfer-non-owner", %{current_user: other_agent})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref = push(socket, "treatment:transfer", %{"target_agent_id" => target_agent.id})

    assert_reply ref, :error, %{reason: "not_assigned_agent"}
    refute_push "treatment:transferred", _payload
  end

  test "invalid target and same agent errors are mapped by the channel" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-transfer-target-errors"}, %{})
    current_agent = logistics_agent_fixture()
    target_agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_010, owner.id)

    assert {:ok, _membership} = Rooms.join_room(current_agent.id, room.id)
    assert {:ok, _membership} = Rooms.join_room(target_agent.id, room.id)
    assert {:ok, _assigned} = Treatments.assign_agent(treatment, current_agent)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-transfer-target-errors", %{current_user: current_agent})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref = push(socket, "treatment:transfer", %{"target_agent_id" => owner.id})
    assert_reply ref, :error, %{reason: "invalid_target_agent"}

    ref = push(socket, "treatment:transfer", %{"target_agent_id" => current_agent.id})
    assert_reply ref, :error, %{reason: "same_agent"}

    ref = push(socket, "treatment:transfer", %{"target_agent_id" => Ecto.UUID.generate()})
    assert_reply ref, :error, %{reason: "invalid_target_agent"}
    refute_push "treatment:transferred", _payload
  end

  test "target without room membership receives invalid_target_agent" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-transfer-target-membership"}, %{})
    current_agent = logistics_agent_fixture()
    target_agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_011, owner.id)

    assert {:ok, _membership} = Rooms.join_room(current_agent.id, room.id)
    assert {:ok, _assigned} = Treatments.assign_agent(treatment, current_agent)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-transfer-target-membership", %{current_user: current_agent})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref = push(socket, "treatment:transfer", %{"target_agent_id" => target_agent.id})

    assert_reply ref, :error, %{reason: "invalid_target_agent"}
    refute_push "treatment:transferred", _payload
  end

  test "current agent without room membership receives not_found" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-transfer-current-membership"}, %{})
    current_agent = logistics_agent_fixture()
    target_agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_012, owner.id)

    assert {:ok, _membership} = Rooms.join_room(target_agent.id, room.id)
    assert {:ok, _assigned} = Treatments.assign_agent(treatment, current_agent)
    socket = %Phoenix.Socket{assigns: %{current_user: current_agent, room_id: room.id}}

    assert {:reply, {:error, %{reason: "not_found"}}, ^socket} =
             RoomChannel.handle_in(
               "treatment:transfer",
               %{"target_agent_id" => target_agent.id},
               socket
             )

    assert transfer_audit_count(treatment, owner) == 0
  end

  test "extra client fields do not control transfer and missing target is stable" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-transfer-payload"}, %{})
    current_agent = logistics_agent_fixture()
    target_agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_013, owner.id)

    assert {:ok, _membership} = Rooms.join_room(current_agent.id, room.id)
    assert {:ok, _membership} = Rooms.join_room(target_agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, current_agent)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-transfer-payload", %{current_user: current_agent})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref =
      push(socket, "treatment:transfer", %{
        "target_agent_id" => target_agent.id,
        "current_agent_id" => Ecto.UUID.generate(),
        "assigned_agent_id" => Ecto.UUID.generate(),
        "assigned_at" => "2000-01-01T00:00:00Z",
        "status" => "open"
      })

    assert_reply ref, :ok, %{
      treatment_id: treatment_id,
      assigned_agent_id: assigned_agent_id,
      assigned_at: assigned_at,
      status: "in_progress"
    }

    assert assigned_agent_id == target_agent.id
    assert assigned_at != assigned.assigned_at
    assert Repo.get!(Treatment, treatment.id).assigned_at == assigned_at

    assert_push "treatment:transferred", %{
      treatment_id: ^treatment_id,
      assigned_agent_id: ^assigned_agent_id,
      assigned_at: ^assigned_at,
      status: "in_progress"
    }

    ref = push(socket, "treatment:transfer", %{})
    assert_reply ref, :error, %{reason: "invalid_target_agent"}
    refute_push "treatment:transferred", _payload
  end

  test "in-progress is the only transferable treatment status" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-transfer-invalid-status"}, %{})
    current_agent = logistics_agent_fixture()
    target_agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_014, owner.id)

    assert {:ok, _membership} = Rooms.join_room(current_agent.id, room.id)
    assert {:ok, _membership} = Rooms.join_room(target_agent.id, room.id)
    assert {:ok, _assigned} = Treatments.assign_agent(treatment, current_agent)
    assert {:ok, resolved} = Treatments.resolve(treatment, current_agent)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-transfer-invalid-status", %{current_user: current_agent})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref = push(socket, "treatment:transfer", %{"target_agent_id" => target_agent.id})

    assert_reply ref, :error, %{reason: "invalid_status"}
    refute_push "treatment:transferred", _payload
    assert Repo.get!(Treatment, treatment.id).status == resolved.status
  end

  test "room without treatment returns not_found without stopping the channel" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-transfer-generic-room"}, %{})
    current_agent = logistics_agent_fixture()

    assert {:ok, room} =
             Rooms.create_room(%{"name" => "Sala generica para transferencia"}, owner.id)

    assert {:ok, _membership} = Rooms.join_room(current_agent.id, room.id)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-transfer-generic-room", %{current_user: current_agent})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    channel_pid = socket.channel_pid
    channel_ref = Process.monitor(channel_pid)

    ref = push(socket, "treatment:transfer", %{"target_agent_id" => Ecto.UUID.generate()})

    assert_reply ref, :error, %{reason: "not_found"}
    refute_receive {:DOWN, ^channel_ref, :process, ^channel_pid, _reason}
    refute_push "treatment:transferred", _payload
  end

  test "commercial member can reopen the room treatment through the channel" do
    {:ok, commercial} = Identity.sync_user(%{"sub" => "channel-reopen-commercial"}, %{})
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_015, commercial.id)

    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)
    assert {:ok, resolved} = Treatments.resolve(assigned, agent)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-reopen-commercial", %{current_user: commercial})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref = push(socket, "treatment:reopen", %{})

    assert_reply ref, :ok, %{
      treatment_id: treatment_id,
      status: "in_progress",
      assigned_agent_id: assigned_agent_id
    }

    assert treatment_id == treatment.id
    assert assigned_agent_id == agent.id

    assert %{
             status: "in_progress",
             assigned_agent_id: ^assigned_agent_id,
             assigned_at: assigned_at,
             resolved_by_id: nil,
             resolved_at: nil
           } = Repo.get!(Treatment, treatment.id)

    assert assigned_at == resolved.assigned_at

    assert_push "treatment:reopened", %{
      treatment_id: ^treatment_id,
      status: "in_progress",
      assigned_agent_id: ^assigned_agent_id,
      assigned_at: ^assigned_at
    }

    retry_ref = push(socket, "treatment:reopen", %{})
    assert_reply retry_ref, :error, %{reason: "invalid_status"}
    refute_push "treatment:reopened", _duplicate

    assert reopened_audit_count(treatment, commercial) == 1
  end

  test "logistics agent member can reopen the room treatment through the channel" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-reopen-logistics-owner"}, %{})
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_016, owner.id)

    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)
    assert {:ok, _resolved} = Treatments.resolve(assigned, agent)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-reopen-logistics", %{current_user: agent})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref = push(socket, "treatment:reopen", %{})

    treatment_id = treatment.id
    agent_id = agent.id
    assert_reply ref, :ok, %{treatment_id: ^treatment_id, status: "in_progress"}

    assert_push "treatment:reopened", %{
      treatment_id: ^treatment_id,
      status: "in_progress",
      assigned_agent_id: ^agent_id,
      assigned_at: assigned_at
    }

    assert assigned_at == assigned.assigned_at
    assert reopened_audit_count(treatment, owner) == 1
  end

  test "authorized user outside the treatment room receives not_found" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-reopen-membership-owner"}, %{})
    {:ok, outsider} = Identity.sync_user(%{"sub" => "channel-reopen-outsider"}, %{})
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_017, owner.id)

    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)
    assert {:ok, resolved} = Treatments.resolve(assigned, agent)
    socket = %Phoenix.Socket{assigns: %{current_user: outsider, room_id: room.id}}

    assert {:reply, {:error, %{reason: "not_found"}}, ^socket} =
             RoomChannel.handle_in("treatment:reopen", %{}, socket)

    assert Repo.get!(Treatment, treatment.id).status == "resolved"
    assert reopened_audit_count(treatment, owner) == 0
    assert Repo.get!(Treatment, treatment.id).assigned_at == resolved.assigned_at
  end

  test "role without reopen permission receives forbidden" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-reopen-forbidden-owner"}, %{})
    agent = logistics_agent_fixture()
    unauthorized = %{owner | role: "unknown"}

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_018, owner.id)

    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)
    assert {:ok, resolved} = Treatments.resolve(assigned, agent)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-reopen-forbidden", %{current_user: unauthorized})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref = push(socket, "treatment:reopen", %{})

    assert_reply ref, :error, %{reason: "forbidden"}
    refute_push "treatment:reopened", _payload
    assert Repo.get!(Treatment, treatment.id).status == resolved.status
    assert reopened_audit_count(treatment, owner) == 0
  end

  test "in-progress treatment returns invalid_status through the channel" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-reopen-invalid-status"}, %{})
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_019, owner.id)

    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
    assert {:ok, _assigned} = Treatments.assign_agent(treatment, agent)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-reopen-invalid-status", %{current_user: agent})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref = push(socket, "treatment:reopen", %{})

    assert_reply ref, :error, %{reason: "invalid_status"}
    refute_push "treatment:reopened", _payload
    assert Repo.get!(Treatment, treatment.id).status == "in_progress"
  end

  test "room without treatment returns not_found when reopening through the channel" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-reopen-generic-room"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Sala genérica para reabertura"}, owner.id)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-reopen-generic-room", %{current_user: owner})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    channel_pid = socket.channel_pid
    channel_ref = Process.monitor(channel_pid)
    ref = push(socket, "treatment:reopen", %{})

    assert_reply ref, :error, %{reason: "not_found"}
    refute_push "treatment:reopened", _payload
    refute_receive {:DOWN, ^channel_ref, :process, ^channel_pid, _reason}
  end

  test "client treatment fields do not control reopening" do
    {:ok, commercial} = Identity.sync_user(%{"sub" => "channel-reopen-payload"}, %{})
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_020, commercial.id)

    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)
    assert {:ok, resolved} = Treatments.resolve(assigned, agent)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-reopen-payload", %{current_user: commercial})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref =
      push(socket, "treatment:reopen", %{
        "status" => "resolved",
        "resolved_by_id" => agent.id,
        "resolved_at" => "2000-01-01T00:00:00Z",
        "assigned_agent_id" => Ecto.UUID.generate()
      })

    assert_reply ref, :ok, %{status: "in_progress", assigned_agent_id: assigned_agent_id}
    assert assigned_agent_id == agent.id

    assert %{status: "in_progress", resolved_by_id: nil, resolved_at: nil} =
             Repo.get!(Treatment, treatment.id)

    assert Repo.get!(Treatment, treatment.id).assigned_at == resolved.assigned_at

    treatment_id = treatment.id
    agent_id = agent.id
    assigned_at = resolved.assigned_at

    assert_push "treatment:reopened", %{
      treatment_id: ^treatment_id,
      status: "in_progress",
      assigned_agent_id: ^agent_id,
      assigned_at: ^assigned_at
    }

    assert reopened_audit_count(treatment, commercial) == 1
  end

  test "stale caller state cannot publish an incorrect reopening event" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-reopen-stale-owner"}, %{})
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_021, owner.id)

    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)
    assert {:ok, stale_resolved} = Treatments.resolve(assigned, agent)

    assert {:ok, persisted_in_progress} =
             stale_resolved
             |> Treatment.changeset(%{
               status: "in_progress",
               resolved_by_id: nil,
               resolved_at: nil
             })
             |> Repo.update()

    assert stale_resolved.status == "resolved"
    assert persisted_in_progress.status == "in_progress"

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-reopen-stale-owner", %{current_user: owner})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref = push(socket, "treatment:reopen", %{})

    assert_reply ref, :error, %{reason: "invalid_status"}
    refute_push "treatment:reopened", _payload
    assert Repo.get!(Treatment, treatment.id).status == "in_progress"
    assert reopened_audit_count(treatment, owner) == 0
  end

  test "concurrent channel reopens publish exactly one event" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-reopen-race-owner"}, %{})
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_022, owner.id)

    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)
    assert {:ok, _resolved} = Treatments.resolve(assigned, agent)

    {:ok, _reply, first_socket} =
      UserSocket
      |> socket("channel-reopen-race-1", %{current_user: owner})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    {:ok, _reply, second_socket} =
      UserSocket
      |> socket("channel-reopen-race-2", %{current_user: owner})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    first_ref = push(first_socket, "treatment:reopen", %{})
    second_ref = push(second_socket, "treatment:reopen", %{})

    assert_reply first_ref, first_status, first_payload
    assert_reply second_ref, second_status, second_payload

    assert [:error, :ok] = Enum.sort([first_status, second_status])

    assert Enum.any?([first_payload, second_payload], fn
             %{reason: "invalid_status"} -> true
             _payload -> false
           end)

    assert_push "treatment:reopened", %{
      treatment_id: treatment_id,
      status: "in_progress",
      assigned_agent_id: assigned_agent_id,
      assigned_at: assigned_at
    }

    assert_push "treatment:reopened", %{
      treatment_id: ^treatment_id,
      status: "in_progress",
      assigned_agent_id: ^assigned_agent_id,
      assigned_at: ^assigned_at
    }

    assert treatment_id == treatment.id
    assert assigned_agent_id == agent.id
    assert assigned_at == assigned.assigned_at
    refute_push "treatment:reopened", _duplicate
    assert reopened_audit_count(treatment, owner) == 1
  end

  test "concurrent channel resolutions publish exactly one event" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-resolution-race-owner"}, %{})
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_013, owner.id)

    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
    assert {:ok, _assigned} = Treatments.assign_agent(treatment, agent)

    {:ok, _reply, first_socket} =
      UserSocket
      |> socket("channel-resolution-race-agent-1", %{current_user: agent})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    {:ok, _reply, second_socket} =
      UserSocket
      |> socket("channel-resolution-race-agent-2", %{current_user: agent})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    first_ref = push(first_socket, "treatment:resolve", %{})
    second_ref = push(second_socket, "treatment:resolve", %{})

    assert_reply first_ref, first_status, first_payload
    assert_reply second_ref, second_status, second_payload

    assert [:error, :ok] = Enum.sort([first_status, second_status])

    assert Enum.any?([first_payload, second_payload], fn
             %{reason: "invalid_status"} -> true
             _payload -> false
           end)

    assert_push "treatment:resolved", %{
      treatment_id: treatment_id,
      status: "resolved",
      resolved_by_id: resolved_by_id,
      resolved_at: resolved_at
    }

    assert_push "treatment:resolved", %{
      treatment_id: ^treatment_id,
      status: "resolved",
      resolved_by_id: ^resolved_by_id,
      resolved_at: ^resolved_at
    }

    assert treatment_id == treatment.id
    assert resolved_by_id == agent.id
    assert resolved_at != nil
    refute_push "treatment:resolved", _duplicate
    assert resolution_audit_count(treatment, agent) == 1
  end

  test "stale caller state cannot trigger a duplicate resolution broadcast" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-resolution-stale-owner"}, %{})
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_014, owner.id)

    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
    assert {:ok, stale_assigned} = Treatments.assign_agent(treatment, agent)
    assert stale_assigned.status == "in_progress"
    assert {:ok, resolved} = Treatments.resolve(stale_assigned, agent)
    assert stale_assigned.status == "in_progress"
    assert resolved.status == "resolved"

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-resolution-stale-agent", %{current_user: agent})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref = push(socket, "treatment:resolve", %{})

    assert_reply ref, :error, %{reason: "invalid_status"}
    refute_push "treatment:resolved", _duplicate
    assert resolution_audit_count(treatment, agent) == 1
  end

  test "commercial user receives forbidden when resolving through the channel" do
    {:ok, commercial} = Identity.sync_user(%{"sub" => "channel-resolution-commercial"}, %{})
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_007, commercial.id)

    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
    assert {:ok, _assigned} = Treatments.assign_agent(treatment, agent)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-resolution-commercial", %{current_user: commercial})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref = push(socket, "treatment:resolve", %{})

    assert_reply ref, :error, %{reason: "forbidden"}
    refute_push "treatment:resolved", _payload

    assert %{status: "in_progress", resolved_by_id: nil, resolved_at: nil} =
             Repo.get!(Treatment, treatment.id)

    assert resolution_audit_count(treatment, commercial) == 0
  end

  test "another logistics agent receives not_assigned_agent when resolving through the channel" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-resolution-other-owner"}, %{})
    assigned_agent = logistics_agent_fixture()
    other_agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_008, owner.id)

    assert {:ok, _membership} = Rooms.join_room(assigned_agent.id, room.id)
    assert {:ok, _membership} = Rooms.join_room(other_agent.id, room.id)
    assert {:ok, _assigned} = Treatments.assign_agent(treatment, assigned_agent)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-resolution-other-agent", %{current_user: other_agent})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref = push(socket, "treatment:resolve", %{})

    assert_reply ref, :error, %{reason: "not_assigned_agent"}
    refute_push "treatment:resolved", _payload

    assert %{status: "in_progress", resolved_by_id: nil, resolved_at: nil} =
             Repo.get!(Treatment, treatment.id)

    assert resolution_audit_count(treatment, other_agent) == 0
  end

  test "resolved treatment returns invalid_status through the channel" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-resolution-status-owner"}, %{})
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_009, owner.id)

    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)
    assert {:ok, resolved} = Treatments.resolve(assigned, agent)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-resolution-invalid-status", %{current_user: agent})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref = push(socket, "treatment:resolve", %{})

    assert_reply ref, :error, %{reason: "invalid_status"}
    refute_push "treatment:resolved", _payload

    assert %{status: "resolved", resolved_by_id: resolved_by_id, resolved_at: resolved_at} =
             Repo.get!(Treatment, treatment.id)

    assert resolved_by_id == resolved.resolved_by_id
    assert resolved_at == resolved.resolved_at
    assert resolution_audit_count(treatment, agent) == 1
  end

  test "room without treatment returns not_found when resolving through the channel" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-resolution-generic-room"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Sala genérica para resolução"}, owner.id)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-resolution-generic-room", %{current_user: owner})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    channel_pid = socket.channel_pid
    channel_ref = Process.monitor(channel_pid)
    ref = push(socket, "treatment:resolve", %{})

    assert_reply ref, :error, %{reason: "not_found"}
    refute_push "treatment:resolved", _payload
    refute_receive {:DOWN, ^channel_ref, :process, ^channel_pid, _reason}
  end

  test "client identity fields do not control who resolves through the channel" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-resolution-payload-owner"}, %{})
    agent = logistics_agent_fixture()
    other_agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_010, owner.id)

    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-resolution-payload-agent", %{current_user: agent})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref =
      push(socket, "treatment:resolve", %{
        "resolved_by_id" => other_agent.id,
        "agent_id" => other_agent.id
      })

    assert_reply ref, :ok, %{resolved_by_id: resolved_by_id}
    assert resolved_by_id == agent.id
    assert Repo.get!(Treatment, assigned.id).resolved_by_id == agent.id
  end

  test "client timestamp and status fields do not control resolution through the channel" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-resolution-fields-owner"}, %{})
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_011, owner.id)

    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-resolution-fields-agent", %{current_user: agent})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref =
      push(socket, "treatment:resolve", %{
        "resolved_at" => "2000-01-01T00:00:00Z",
        "status" => "closed"
      })

    assert_reply ref, :ok, %{status: "resolved", resolved_at: resolved_at}
    refute to_string(resolved_at) == "2000-01-01T00:00:00Z"

    assert %{status: "resolved", resolved_at: persisted_resolved_at} =
             Repo.get!(Treatment, assigned.id)

    assert persisted_resolved_at == resolved_at
  end

  test "unexpected treatment resolution result returns a safe fallback" do
    agent = logistics_agent_fixture()
    socket = %Phoenix.Socket{assigns: %{current_user: agent, room_id: "invalid-room-id"}}

    assert {:reply, {:error, %{reason: "treatment_resolution_failed"}}, ^socket} =
             RoomChannel.handle_in("treatment:resolve", %{}, socket)
  end

  test "commercial user receives forbidden when assigning through the channel" do
    {:ok, commercial} = Identity.sync_user(%{"sub" => "channel-treatment-commercial"}, %{})

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_001, commercial.id)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-treatment-commercial", %{current_user: commercial})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref = push(socket, "treatment:assign_to_me", %{})

    assert_reply ref, :error, %{reason: "forbidden"}
    refute_push "treatment:agent_assigned", _payload
    assert %{assigned_agent_id: nil, assigned_at: nil} = Repo.get!(Treatment, treatment.id)
  end

  test "another agent receives already_assigned through the channel" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-treatment-owner-two"}, %{})
    first_agent = logistics_agent_fixture()
    second_agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_002, owner.id)

    assert {:ok, _membership} = Rooms.join_room(first_agent.id, room.id)
    assert {:ok, _membership} = Rooms.join_room(second_agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, first_agent)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-treatment-agent-two", %{current_user: second_agent})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref = push(socket, "treatment:assign_to_me", %{})

    assert_reply ref, :error, %{reason: "already_assigned"}
    refute_push "treatment:agent_assigned", _payload

    assert %{assigned_agent_id: assigned_agent_id, assigned_at: assigned_at} =
             Repo.get!(Treatment, treatment.id)

    assert assigned_agent_id == first_agent.id
    assert assigned_at == assigned.assigned_at
  end

  test "same agent retry preserves assigned_at through the channel" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-treatment-owner-three"}, %{})
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_003, owner.id)

    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-treatment-agent-three", %{current_user: agent})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    first_ref = push(socket, "treatment:assign_to_me", %{})
    assert_reply first_ref, :ok, %{assigned_at: first_assigned_at}
    assert_push "treatment:agent_assigned", %{assigned_at: ^first_assigned_at}

    second_ref = push(socket, "treatment:assign_to_me", %{})
    assert_reply second_ref, :ok, %{assigned_at: second_assigned_at}
    refute_push "treatment:agent_assigned", _duplicate

    assert second_assigned_at == first_assigned_at
    agent_id = agent.id

    assert %{assigned_agent_id: ^agent_id, assigned_at: ^first_assigned_at} =
             Repo.get!(Treatment, treatment.id)
  end

  test "stale caller state does not broadcast an idempotent assignment retry" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-treatment-stale-owner"}, %{})
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: stale_treatment, room: room}} =
             Treatments.open_for_order(9_998_044_012, owner.id)

    assert stale_treatment.assigned_agent_id == nil
    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(stale_treatment, agent)
    assert assigned.assigned_agent_id == agent.id
    assert stale_treatment.assigned_agent_id == nil

    assert {:ok, idempotent_treatment, :idempotent} =
             Treatments.assign_agent_for_room(room.id, agent)

    assert idempotent_treatment.assigned_agent_id == agent.id
    assert idempotent_treatment.assigned_at == assigned.assigned_at

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-treatment-stale-agent", %{current_user: agent})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref = push(socket, "treatment:assign_to_me", %{})

    assert_reply ref, :ok, %{assigned_at: assigned_at}
    refute_push "treatment:agent_assigned", _duplicate
    assert assigned_at == assigned.assigned_at
  end

  test "client identity and timestamp fields do not control assignment" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-treatment-owner-four"}, %{})
    agent = logistics_agent_fixture()
    other_agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_004, owner.id)

    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-treatment-agent-four", %{current_user: agent})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref =
      push(socket, "treatment:assign_to_me", %{
        "agent_id" => other_agent.id,
        "assigned_agent_id" => other_agent.id,
        "assigned_at" => "2000-01-01T00:00:00Z"
      })

    assert_reply ref, :ok, %{assigned_agent_id: assigned_agent_id, assigned_at: assigned_at}
    assert assigned_agent_id == agent.id
    refute assigned_at == "2000-01-01T00:00:00Z"
    assert Repo.get!(Treatment, treatment.id).assigned_agent_id == agent.id
  end

  test "room without treatment returns not_found through the channel" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-generic-room"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Sala genérica"}, owner.id)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-generic-room", %{current_user: owner})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    channel_pid = socket.channel_pid
    channel_ref = Process.monitor(channel_pid)
    ref = push(socket, "treatment:assign_to_me", %{})

    assert_reply ref, :error, %{reason: "not_found"}
    refute_push "treatment:agent_assigned", _payload
    refute_receive {:DOWN, ^channel_ref, :process, ^channel_pid, _reason}
  end

  test "revoked membership cannot assign through an existing channel" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-revoked-owner"}, %{})
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_044_005, owner.id)

    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-revoked-agent", %{current_user: agent})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    assert {:ok, 1} = Rooms.leave_room(agent.id, room.id)

    ref = push(socket, "treatment:assign_to_me", %{})

    assert_reply ref, :error, %{reason: "forbidden"}
    refute_push "treatment:agent_assigned", _payload

    assert %{assigned_agent_id: nil, assigned_at: nil, status: "open"} =
             Repo.get!(Treatment, treatment.id)
  end

  test "cannot delete a message from another room through the current room channel" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-owner"}, %{})
    {:ok, current_room} = Rooms.create_room(%{"name" => "Sala atual"}, owner.id)
    {:ok, other_room} = Rooms.create_room(%{"name" => "Outra sala"}, owner.id)

    {:ok, other_message} =
      Messages.create_message(%{"content" => "Mensagem isolada"}, owner.id, other_room.id)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-owner", %{current_user: owner})
      |> subscribe_and_join(RoomChannel, "room:#{current_room.id}")

    ref = push(socket, "message:delete", %{"message_id" => other_message.id})

    assert_reply ref, :error, %{reason: "not_found"}
    assert Messages.get_message(other_message.id)
  end

  test "rejects a room rejoin after the user's membership is revoked" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "rejoin-owner"}, %{})
    {:ok, member} = Identity.sync_user(%{"sub" => "rejoin-member"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Sala de reentrada"}, owner.id)
    assert {:ok, _membership} = Rooms.join_room(member.id, room.id)

    {:ok, _reply, _socket} =
      UserSocket
      |> socket("rejoin-member", %{current_user: member})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    assert {:ok, 1} = Rooms.leave_room(member.id, room.id)

    assert {:error, %{reason: "unauthorized"}} =
             UserSocket
             |> socket("rejoin-member-after-revocation", %{current_user: member})
             |> subscribe_and_join(RoomChannel, "room:#{room.id}")
  end

  test "cannot delete a message already read by another room member" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-read-owner"}, %{})
    {:ok, reader} = Identity.sync_user(%{"sub" => "channel-reader"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Sala com leitura"}, owner.id)
    assert {:ok, _membership} = Rooms.join_room(reader.id, room.id)

    assert {:ok, message} =
             Messages.create_message(%{"content" => "Mensagem lida"}, owner.id, room.id)

    assert :ok = Messages.mark_as_read(message.id, reader.id)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-read-owner", %{current_user: owner})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref = push(socket, "message:delete", %{"message_id" => message.id})

    assert_reply ref, :error, %{reason: "already_read"}
    assert Messages.get_message(message.id)
  end

  test "author can delete an unread message without crashing the channel" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-delete-owner"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Sala para excluir"}, owner.id)

    assert {:ok, message} =
             Messages.create_message(%{"content" => "Mensagem removível"}, owner.id, room.id)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-delete-owner", %{current_user: owner})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    channel_pid = socket.channel_pid
    channel_ref = Process.monitor(channel_pid)
    ref = push(socket, "message:delete", %{"message_id" => message.id})

    assert_reply ref, :ok
    refute_receive {:DOWN, ^channel_ref, :process, ^channel_pid, _reason}
    assert Messages.get_message(message.id) == nil
  end

  test "creating a message pushes it once and keeps the channel alive" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-create-owner"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Sala para criar"}, owner.id)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-create-owner", %{current_user: owner})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    channel_pid = socket.channel_pid
    channel_ref = Process.monitor(channel_pid)
    client_id = Ecto.UUID.generate()
    ref = push(socket, "message:new", %{"content" => "Mensagem nova", "client_id" => client_id})

    assert_reply ref, :ok

    assert_push "message:new", %{
      content: "Mensagem nova",
      room_id: room_id
    }

    assert room_id == room.id
    assert Messages.list_messages(room.id) |> length() == 1
    refute_push "message:new", _duplicate
    refute_receive {:DOWN, ^channel_ref, :process, ^channel_pid, _reason}

    delete_ref =
      push(socket, "message:delete", %{
        "message_id" => List.first(Messages.list_messages(room.id)).id
      })

    assert_reply delete_ref, :ok
  end

  test "creates an attachment-only message through the channel" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-attachment-owner"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Sala com anexo"}, owner.id)

    assert {:ok, attachment, _upload_url} =
             Attachments.presign_upload(
               owner.id,
               room.id,
               %{
                 "filename" => "documento.pdf",
                 "content_type" => "application/pdf",
                 "size" => 128
               },
               presigner: Chat.TestSupport.MessageAttachmentPresigner
             )

    attachment
    |> Ecto.Changeset.change(status: :available)
    |> Repo.update!()

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-attachment-owner", %{current_user: owner})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    ref =
      push(socket, "message:new", %{
        "content" => "",
        "client_id" => Ecto.UUID.generate(),
        "attachment_ids" => [attachment.id]
      })

    assert_reply ref, :ok

    assert_receive {:message_created, %{content: "", attachments: [%{id: attachment_id}]}}
    assert attachment_id == attachment.id
    assert [%{content: ""}] = Messages.list_messages(room.id)
    assert Repo.get!(MessageAttachment, attachment.id).message_id != nil
  end

  test "reusing a client id does not create or broadcast a duplicate message" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-idempotent-owner"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Sala idempotente"}, owner.id)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-idempotent-owner", %{current_user: owner})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    client_id = Ecto.UUID.generate()
    payload = %{"content" => "Mensagem idempotente", "client_id" => client_id}

    first_ref = push(socket, "message:new", payload)
    assert_reply first_ref, :ok
    assert_push "message:new", %{content: "Mensagem idempotente"}

    second_ref = push(socket, "message:new", payload)
    assert_reply second_ref, :ok
    refute_push "message:new", _duplicate
    assert [%{content: "Mensagem idempotente"}] = Messages.list_messages(room.id)
  end

  test "rejects malformed message payloads without terminating the channel" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-invalid-owner"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Sala inválida"}, owner.id)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-invalid-owner", %{current_user: owner})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    channel_pid = socket.channel_pid
    channel_ref = Process.monitor(channel_pid)
    ref = push(socket, "message:new", %{"content" => []})

    assert_reply ref, :error, %{reason: "invalid_message"}
    refute_receive {:DOWN, ^channel_ref, :process, ^channel_pid, _reason}
  end

  test "read receipt updates are pushed without crashing the channel" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "channel-receipt-owner"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Sala com recibos"}, owner.id)

    {:ok, _reply, socket} =
      UserSocket
      |> socket("channel-receipt-owner", %{current_user: owner})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    channel_pid = socket.channel_pid
    channel_ref = Process.monitor(channel_pid)
    message_ids = [Ecto.UUID.generate()]

    assert :ok =
             Chat.Broadcaster.broadcast_read_receipts_updated(room.id, owner.id, message_ids)

    assert_push "read_receipts:updated", %{
      user_id: user_id,
      message_ids: ^message_ids
    }

    assert user_id == owner.id
    refute_receive {:DOWN, ^channel_ref, :process, ^channel_pid, _reason}
  end

  defp logistics_agent_fixture do
    %User{}
    |> User.auth_changeset(%{
      email: "channel-agent-#{System.unique_integer([:positive])}@example.com",
      username: "channel-agent-#{System.unique_integer([:positive])}",
      role: "logistics_agent"
    })
    |> Repo.insert!()
  end

  defp resolution_audit_count(treatment, user) do
    treatment.id
    |> Treatments.list_audit_events(user.id)
    |> Enum.count(&(&1.event_type == "treatment_resolved"))
  end

  defp reopened_audit_count(treatment, user) do
    treatment.id
    |> Treatments.list_audit_events(user.id)
    |> Enum.count(&(&1.event_type == "treatment_reopened"))
  end

  defp transfer_audit_count(treatment, user) do
    treatment.id
    |> Treatments.list_audit_events(user.id)
    |> Enum.count(&(&1.event_type == "treatment_transferred"))
  end
end
