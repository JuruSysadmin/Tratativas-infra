defmodule Chat.AuthenticatorSpy do
  @moduledoc false

  def authenticate(token, _opts) do
    test_pid = Application.fetch_env!(:chat, :authenticator_spy_pid)
    user = Application.fetch_env!(:chat, :authenticator_spy_user)

    send(test_pid, {:authenticated, token})
    {:ok, user, %{"sub" => user.username}}
  end
end
