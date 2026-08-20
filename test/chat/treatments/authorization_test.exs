defmodule Chat.Treatments.AuthorizationTest do
  use ExUnit.Case, async: true

  alias Chat.Accounts.User
  alias Chat.Treatments.Authorization

  @permissions [
    "treatment.assign",
    "treatment.resolve",
    "treatment.reopen",
    "treatment.unassign"
  ]

  test "logistics agents can perform every treatment action" do
    user = %User{role: "logistics_agent"}

    assert Enum.all?(@permissions, &Authorization.allowed?(user, &1))
  end

  test "commercial users cannot assign or unassign treatments" do
    user = %User{role: "commercial"}

    refute Authorization.allowed?(user, "treatment.assign")
    refute Authorization.allowed?(user, "treatment.unassign")
  end

  test "commercial users can resolve and reopen treatments" do
    user = %User{role: "commercial"}

    assert Authorization.allowed?(user, "treatment.resolve")
    assert Authorization.allowed?(user, "treatment.reopen")
  end

  test "denied permissions return a stable authorization error" do
    user = %User{role: "commercial"}

    assert {:error, :forbidden} = Authorization.authorize(user, "treatment.assign")
    assert :ok = Authorization.authorize(user, "treatment.resolve")
  end

  test "unknown roles and permissions are denied" do
    assert {:error, :forbidden} =
             Authorization.authorize(%User{role: "unknown"}, "treatment.assign")

    refute Authorization.allowed?(%User{role: "logistics_agent"}, "treatment.delete")
  end
end
