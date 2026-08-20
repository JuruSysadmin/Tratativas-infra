defmodule Chat.Accounts do
  @moduledoc "User persistence and synchronization for externally authenticated accounts."

  alias Chat.Accounts.User
  alias Chat.Repo
  import Ecto.Query

  def get_user(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(User, uuid)
      :error -> nil
    end
  end

  def get_user_by_email(email) do
    Repo.get_by(User, email: email)
  end

  def get_user_by_username(username) do
    Repo.get_by(User, username: username)
  end

  def find_or_create_external_user(attrs) do
    email = attr(attrs, :email)
    provider = attr(attrs, :auth_provider)
    subject = attr(attrs, :auth_subject)

    case Repo.one(
           from user in User,
             where: user.auth_provider == ^provider and user.auth_subject == ^subject
         ) do
      nil -> create_or_update_legacy_user(email, provider, attrs)
      user -> update_external_user(user, attrs)
    end
  end

  defp attr(attrs, key), do: attrs[key] || attrs[Atom.to_string(key)]

  defp create_or_update_legacy_user(email, provider, attrs) do
    case legacy_external_user(email, provider) do
      nil -> create_external_user(email, provider, attrs)
      user -> update_external_user(user, attrs)
    end
  end

  defp create_external_user(email, provider, attrs) do
    case get_user_by_email(email) do
      nil ->
        %User{}
        |> User.external_auth_changeset(Map.put(attrs, :auth_provider, provider))
        |> Repo.insert()

      _user ->
        {:error, :email_already_in_use}
    end
  end

  defp update_external_user(user, attrs) do
    user
    |> User.external_auth_changeset(attrs)
    |> Repo.update()
  end

  defp legacy_external_user(email, "external") do
    Repo.one(
      from user in User,
        where:
          user.email == ^email and user.auth_provider == "external" and
            is_nil(user.auth_subject)
    )
  end

  defp legacy_external_user(_email, _provider), do: nil

  def update_user(%User{} = user, attrs) do
    user
    |> User.status_changeset(attrs)
    |> Repo.update()
  end

  def list_users do
    Repo.all(User)
  end
end
