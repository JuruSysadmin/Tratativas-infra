defmodule Chat.Treatments.AuthorizationTest do
  use ExUnit.Case, async: true

  alias Chat.Accounts.User
  alias Chat.Treatments.Authorization

  @permissions [
    "treatment.assign",
    "treatment.resolve",
    "treatment.reopen",
    "treatment.unassign",
    "treatment.transfer"
  ]

  test "logistics agents can perform every treatment action" do
    user = %User{role: "logistics_agent"}

    Enum.each(@permissions, fn permission ->
      assert Authorization.allowed?(user, permission),
             "expected logistics_agent to allow #{permission}"
    end)
  end

  test "commercial users can only reopen treatments for now" do
    user = %User{role: "commercial"}

    refute Authorization.allowed?(user, "treatment.assign")
    refute Authorization.allowed?(user, "treatment.resolve")
    assert Authorization.allowed?(user, "treatment.reopen")
    refute Authorization.allowed?(user, "treatment.unassign")
    refute Authorization.allowed?(user, "treatment.transfer")
  end

  test "denied permissions return a stable authorization error" do
    user = %User{role: "commercial"}

    assert {:error, :forbidden} = Authorization.authorize(user, "treatment.assign")
    assert :ok = Authorization.authorize(user, "treatment.reopen")
  end

  test "unknown roles and permissions are denied" do
    assert {:error, :forbidden} =
             Authorization.authorize(%User{role: "unknown"}, "treatment.assign")

    refute Authorization.allowed?(%User{role: "logistics_agent"}, "treatment.delete")
  end

  test "nil roles are denied by both authorization APIs" do
    user = %User{role: nil}

    refute Authorization.allowed?(user, "treatment.reopen")
    assert {:error, :forbidden} = Authorization.authorize(user, "treatment.reopen")
  end

  test "invalid authorization arguments are denied" do
    assert {:error, :forbidden} = Authorization.authorize(nil, "treatment.reopen")
    refute Authorization.allowed?(nil, "treatment.reopen")

    user = %User{role: "logistics_agent"}

    assert {:error, :forbidden} = Authorization.authorize(user, nil)
    refute Authorization.allowed?(user, nil)
  end

  test "room access separates membership reading from operational responsibility" do
    commercial = %User{id: "commercial", role: "commercial"}
    current_agent = %User{id: "current", role: "logistics_agent"}
    former_agent = %User{id: "former", role: "logistics_agent"}

    assert :ok = Authorization.authorize_room_action(commercial, "other", :read, true)
    assert :ok = Authorization.authorize_room_action(commercial, "other", :write, true)
    assert :ok = Authorization.authorize_room_action(commercial, "other", :lifecycle, true)

    assert :ok = Authorization.authorize_room_action(current_agent, current_agent.id, :read, true)

    assert :ok =
             Authorization.authorize_room_action(current_agent, current_agent.id, :write, true)

    assert :ok =
             Authorization.authorize_room_action(
               current_agent,
               current_agent.id,
               :lifecycle,
               true
             )

    assert :ok = Authorization.authorize_room_action(former_agent, "current", :read, true)

    assert {:error, :not_assigned_agent} =
             Authorization.authorize_room_action(former_agent, "current", :write, true)

    assert {:error, :not_assigned_agent} =
             Authorization.authorize_room_action(former_agent, "current", :lifecycle, true)

    assert {:error, :forbidden} =
             Authorization.authorize_room_action(current_agent, current_agent.id, :read, false)
  end
end
