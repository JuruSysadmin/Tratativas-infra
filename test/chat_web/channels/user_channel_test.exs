defmodule ChatWeb.UserChannelTest do
  use Chat.DataCase, async: false

  import Phoenix.ChannelTest

  alias Chat.Accounts.User
  alias Chat.Auth.Identity
  alias Chat.Repo
  alias ChatWeb.UserChannel
  alias ChatWeb.UserSocket

  @endpoint ChatWeb.Endpoint

  test "user can join only their own private notification channel" do
    user = user_fixture("private-channel-user")
    other_user = user_fixture("private-channel-other-user")

    assert {:ok, %{}, _socket} =
             UserSocket
             |> socket("private-channel-own", %{current_user: user})
             |> subscribe_and_join(UserChannel, "user:#{user.id}")

    assert {:error, %{reason: "forbidden"}} =
             UserSocket
             |> socket("private-channel-other", %{current_user: user})
             |> subscribe_and_join(UserChannel, "user:#{other_user.id}")
  end

  test "forwards assigned room messages to the connected user" do
    user = user_fixture("private-channel-recipient")

    assert {:ok, %{}, _socket} =
             UserSocket
             |> socket("private-channel-recipient", %{current_user: user})
             |> subscribe_and_join(UserChannel, "user:#{user.id}")

    Phoenix.PubSub.broadcast(
      Chat.PubSub,
      "user:#{user.id}",
      {:assigned_room_message_created,
       %{room_id: Ecto.UUID.generate(), message_id: Ecto.UUID.generate()}}
    )

    assert_push "room:message:new", %{room_id: _, message_id: _}
  end

  test "forwards mention events to the connected user" do
    user = user_fixture("private-channel-mention-recipient")

    assert {:ok, %{}, _socket} =
             UserSocket
             |> socket("private-channel-mention-recipient", %{current_user: user})
             |> subscribe_and_join(UserChannel, "user:#{user.id}")

    payload = %{room_id: Ecto.UUID.generate(), message_id: Ecto.UUID.generate()}

    Phoenix.PubSub.broadcast(Chat.PubSub, "user:#{user.id}", {:mention_created, payload})

    assert_push "mention:created", ^payload
  end

  test "forwards treatment assignment events to the connected user" do
    user = user_fixture("private-channel-assignment-recipient")

    assert {:ok, %{}, _socket} =
             UserSocket
             |> socket("private-channel-assignment-recipient", %{current_user: user})
             |> subscribe_and_join(UserChannel, "user:#{user.id}")

    payload = %{treatment_id: Ecto.UUID.generate(), room_id: Ecto.UUID.generate()}

    Phoenix.PubSub.broadcast(
      Chat.PubSub,
      "user:#{user.id}",
      {:treatment_assigned, payload}
    )

    assert_push "treatment:assigned", ^payload
  end

  test "handle_out forwards the event and preserves the socket" do
    user = user_fixture("private-channel-handle-out")

    assert {:ok, %{}, socket} =
             UserSocket
             |> socket("private-channel-handle-out", %{current_user: user})
             |> subscribe_and_join(UserChannel, "user:#{user.id}")

    payload = %{room_id: Ecto.UUID.generate(), message_id: Ecto.UUID.generate()}

    assert {:noreply, ^socket} = UserChannel.handle_out("room:message:new", payload, socket)
    assert_push "room:message:new", ^payload
  end

  defp user_fixture(subject) do
    {:ok, user} = Identity.sync_user(%{"sub" => subject}, %{})
    Repo.get!(User, user.id)
  end
end
