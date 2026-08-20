defmodule Chat.AccountsTest do
  use Chat.DataCase, async: true

  alias Chat.Accounts

  test "returns nil for an invalid user id" do
    assert Accounts.get_user("not-a-uuid") == nil
  end
end
