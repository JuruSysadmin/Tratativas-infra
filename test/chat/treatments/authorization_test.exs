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
end
