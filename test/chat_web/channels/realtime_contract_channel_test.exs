defmodule ChatWeb.RealtimeContractChannelTest do
  use Chat.DataCase, async: false

  import Phoenix.ChannelTest

  alias Chat.Accounts.User
  alias Chat.Auth.Identity
  alias Chat.Repo
  alias Chat.Rooms
  alias Chat.Treatments
  alias Chat.Treatments.Treatment
  alias ChatWeb.RoomChannel
  alias ChatWeb.UserSocket

  @endpoint ChatWeb.Endpoint

  test "message create, update and remove replies have the broadcast representation" do
    {:ok, user} = Identity.sync_user(%{"sub" => "realtime-contract-message"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Contrato de mensagens"}, user.id)

    {:ok, _join, socket} =
      UserSocket
      |> socket("realtime-contract-message", %{current_user: user})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    create_ref =
      push(socket, "message:new", %{
        "content" => "Mensagem contratual",
        "client_id" => Ecto.UUID.generate()
      })

    assert_reply create_ref, :ok, created_reply
    assert_push "message:new", created_broadcast
    assert created_reply == created_broadcast
    room_id = room.id
    user_id = user.id
    assert %{id: _, room_id: ^room_id, client_id: _, user: %{id: ^user_id}} = created_reply

    edit_ref =
      push(socket, "message:edit", %{
        "message_id" => created_reply.id,
        "content" => "Mensagem atualizada"
      })

    assert_reply edit_ref, :ok, updated_reply
    assert_push "message:updated", updated_broadcast
    assert updated_reply == updated_broadcast
    assert updated_reply.content == "Mensagem atualizada"

    delete_ref = push(socket, "message:delete", %{"message_id" => created_reply.id})

    assert_reply delete_ref, :ok, removed_reply
    assert_push "message:deleted", removed_broadcast
    assert removed_reply == removed_broadcast
    assert removed_reply == %{id: created_reply.id, room_id: room.id}
  end

  test "treatment snapshot, lifecycle reply and broadcast use the same complete projection" do
    {:ok, owner} = Identity.sync_user(%{"sub" => "realtime-contract-treatment"}, %{})
    agent = logistics_agent_fixture()

    assert {:ok, %{treatment: treatment, room: room}} =
             Treatments.open_for_order(9_998_099_001, owner.id)

    assert {:ok, _membership} = Rooms.join_room(agent.id, room.id)
    assert {:ok, assigned} = Treatments.assign_agent(treatment, agent)

    expected_keys = [
      :id,
      :treatment_id,
      :room_id,
      :order_id,
      :protocol,
      :status,
      :assigned_agent_id,
      :assigned_agent_username,
      :assigned_agent_name,
      :assigned_at,
      :resolved_by_id,
      :resolved_at,
      :closed_by_id,
      :closed_at,
      :inserted_at,
      :can_assign,
      :reason
    ]

    {:ok, join_payload, socket} =
      UserSocket
      |> socket("realtime-contract-treatment", %{current_user: agent})
      |> subscribe_and_join(RoomChannel, "room:#{room.id}")

    assert Map.keys(join_payload) |> Enum.sort() == Enum.sort(expected_keys)
    assert join_payload.treatment_id == treatment.id
    assert join_payload.assigned_agent_id == agent.id
    assert join_payload.assigned_agent_username == agent.username
    assert join_payload.assigned_agent_name == agent.username

    resolve_ref = push(socket, "treatment:resolve", %{})
    assert_reply resolve_ref, :ok, reply_payload
    assert_push "treatment:resolved", broadcast_payload
    assert reply_payload == broadcast_payload
    assert Map.keys(reply_payload) |> Enum.sort() == Enum.sort(expected_keys)
    assert reply_payload.status == "resolved"
    assert reply_payload.assigned_at == assigned.assigned_at
    assert reply_payload.resolved_by_id == agent.id
    assert is_struct(Repo.get!(Treatment, treatment.id), Treatment)
  end

  defp logistics_agent_fixture do
    %User{}
    |> User.auth_changeset(%{
      email: "contract-agent-#{System.unique_integer([:positive])}@example.com",
      username: "contract-agent-#{System.unique_integer([:positive])}",
      role: "logistics_agent"
    })
    |> Repo.insert!()
  end
end
