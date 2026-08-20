defmodule ChatWeb.UserAuth do
  @moduledoc false

  import Phoenix.Component
  import Phoenix.LiveView

  alias Chat.Accounts

  def on_mount(:ensure_authenticated, _params, session, socket) do
    case session["user_id"] && Accounts.get_user(session["user_id"]) do
      nil ->
        {:halt, redirect(socket, to: "/")}

      user ->
        {:cont,
         socket
         |> assign(:current_user, user)
         |> assign(:current_scope, user)}
    end
  end
end
