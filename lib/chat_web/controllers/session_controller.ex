defmodule ChatWeb.SessionController do
  use ChatWeb, :controller

  require Logger

  alias Chat.Auth.Login

  def create(conn, %{"username" => username, "password" => password}) do
    login_module = Application.get_env(:chat, :auth_login_module, Login)

    case login_module.authenticate(username, password) do
      {:ok, user, _token, _response} ->
        conn
        |> clear_session()
        |> configure_session(renew: true)
        |> put_session(:user_id, user.id)
        |> redirect(to: ~p"/home")

      {:error, :invalid_credentials} ->
        conn
        |> put_flash(:login_username, username)
        |> put_flash(:error, "Usuário ou senha incorretos. Tente novamente.")
        |> redirect(to: ~p"/")

      {:error, reason} ->
        Logger.warning("authentication failed: #{inspect(reason)}")

        conn
        |> put_flash(:login_username, username)
        |> put_flash(:error, "Não foi possível acessar o servidor de autenticação")
        |> redirect(to: ~p"/")
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Informe usuário e senha")
    |> redirect(to: ~p"/")
  end

  def delete(conn, _params) do
    conn
    |> clear_session()
    |> configure_session(drop: true)
    |> redirect(to: ~p"/")
  end
end
