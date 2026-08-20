defmodule Chat.Auth.E2ELogin do
  @moduledoc false

  alias Chat.Auth.Identity
  alias Chat.Rooms

  def authenticate("e2e-user", "e2e-password") do
    {:ok, user} =
      Identity.sync_user(%{"sub" => "e2e-user"}, %{"username" => "e2e-user"})

    case Rooms.get_user_rooms(user.id) do
      [] ->
        {:ok, _room} = Rooms.create_room(%{"name" => "E2E Chat"}, user.id)
        :ok

      _rooms ->
        :ok
    end

    {:ok, user, nil, %{}}
  end

  def authenticate(_username, _password), do: {:error, :invalid_credentials}
end
