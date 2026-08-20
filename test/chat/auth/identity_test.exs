defmodule Chat.Auth.IdentityTest do
  use Chat.DataCase, async: true

  alias Chat.Accounts
  alias Chat.Accounts.User
  alias Chat.Auth.Identity

  test "synchronizes validated external claims into an Ecto user" do
    claims = %{
      "sub" => "alice",
      "email" => "alice@example.com",
      "matricula" => 123,
      "codusur" => 9,
      "filial" => 2
    }

    assert {:ok, %User{} = user} = Identity.sync_user(claims, %{"username" => "Alice"})
    assert user.email == "alice@example.com"
    assert user.username == "Alice"
    assert user.matricula == "123"
    assert user.auth_provider == "external"
    assert user.auth_subject == "alice"
    assert user.role == "commercial"
  end

  test "preserves a locally assigned role during external synchronization" do
    {:ok, user} =
      %User{}
      |> User.auth_changeset(%{
        email: "logistics@example.com",
        username: "logistics-agent",
        role: "logistics_agent",
        auth_provider: "external",
        auth_subject: "logistics-sub"
      })
      |> Repo.insert()

    assert {:ok, synchronized_user} =
             Identity.sync_user(
               %{"sub" => "logistics-sub", "email" => "logistics@example.com"},
               %{}
             )

    assert synchronized_user.id == user.id
    assert synchronized_user.role == "logistics_agent"
  end

  test "rejects an unsupported user role" do
    changeset =
      User.auth_changeset(%User{}, %{
        email: "invalid-role@example.com",
        username: "invalid-role",
        role: "admin"
      })

    assert "is invalid" in errors_on(changeset).role
  end

  test "maps the database role constraint to the changeset" do
    changeset =
      %User{}
      |> Ecto.Changeset.change(
        email: "database-role@example.com",
        username: "database-role",
        role: "admin"
      )
      |> Ecto.Changeset.check_constraint(:role, name: :users_role_check)

    assert {:error, changeset} = Repo.insert(changeset)
    assert "is invalid" in errors_on(changeset).role
  end

  test "uses the provider subject as the stable identity when the email changes" do
    assert {:ok, first_user} =
             Identity.sync_user(
               %{"sub" => "mutable-email", "email" => "before@example.com"},
               %{}
             )

    assert {:ok, second_user} =
             Identity.sync_user(
               %{"sub" => "mutable-email", "email" => "after@example.com"},
               %{}
             )

    assert second_user.id == first_user.id
    assert second_user.auth_subject == "mutable-email"
    assert second_user.email == "after@example.com"
  end

  test "rejects an external identity whose email belongs to another identity" do
    assert {:ok, _user} =
             Identity.sync_user(%{"sub" => "first-sub", "email" => "collision@example.com"}, %{})

    assert {:error, :email_already_in_use} =
             Identity.sync_user(%{"sub" => "second-sub", "email" => "collision@example.com"}, %{})
  end

  test "does not convert a local account when an external identity uses its email" do
    local_user =
      %User{}
      |> User.auth_changeset(%{
        email: "local@example.com",
        username: "local-user",
        auth_provider: "local"
      })
      |> Repo.insert!()

    assert {:error, :email_already_in_use} =
             Identity.sync_user(%{"sub" => "local-sub", "email" => local_user.email}, %{})

    assert Repo.get!(User, local_user.id).auth_provider == "local"
  end

  test "backfills the subject for an existing external account after migration" do
    legacy_user =
      %User{}
      |> User.auth_changeset(%{
        email: "legacy@example.com",
        username: "legacy-user",
        auth_provider: "external"
      })
      |> Repo.insert!()

    assert {:ok, user} =
             Identity.sync_user(%{"sub" => "legacy-sub", "email" => legacy_user.email}, %{})

    assert user.id == legacy_user.id
    assert user.auth_subject == "legacy-sub"
  end

  test "requires the subject claim" do
    assert {:error, :invalid_claims} = Identity.sync_user(%{}, %{})
  end

  test "rejects claims with unsupported profile value types" do
    claims = %{
      "sub" => "invalid-profile-claims",
      "matricula" => %{"unexpected" => "map"}
    }

    assert {:error, :invalid_claims} = Identity.sync_user(claims, %{})
  end

  test "rejects a provider response with an unsupported shape" do
    assert {:error, :invalid_claims} =
             Identity.sync_user(%{"sub" => "invalid-provider-response"}, [])
  end

  test "external users can update their presence status without a password" do
    {:ok, user} =
      Identity.sync_user(%{"sub" => "presence-user", "email" => "presence@example.com"}, %{})

    assert {:ok, updated_user} = Accounts.update_user(user, %{status: "away"})
    assert updated_user.status == "away"
  end
end
