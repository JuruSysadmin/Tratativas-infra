defmodule Chat.AuthIdentityStub do
  @moduledoc false

  alias Chat.Accounts.User

  def sync_user(%{"sub" => "alice"}, %{}) do
    {:ok, %User{id: Ecto.UUID.generate(), username: "alice", email: "alice@example.com"}}
  end
end
