defmodule Chat.AuthLoginStub do
  @moduledoc false

  alias Chat.Accounts.User

  def authenticate("alice", _password) do
    {:ok, %User{id: "03c82a75-5634-4362-a98c-32666ea319ca", username: "alice"}, "valid-token",
     %{}}
  end

  def authenticate("invalid-issuer", _password), do: {:error, :invalid_issuer}

  def authenticate(_username, _password), do: {:error, :invalid_credentials}
end
