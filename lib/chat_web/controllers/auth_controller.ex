defmodule ChatWeb.AuthController do
  @moduledoc "HTTP endpoints for login and token refresh operations."

  use ChatWeb, :controller

  alias Chat.Auth.{External, Login, Token}

  def login(conn, %{"email" => username, "password" => password}) do
    authenticate(conn, username, password)
  end

  def login(conn, %{"username" => username, "password" => password}) do
    authenticate(conn, username, password)
  end

  def login(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "missing_email_or_username_and_password"})
  end

  def refresh(conn, %{"token" => refresh_token}) do
    with {:ok, token, auth_response} <- External.refresh(refresh_token),
         {:ok, _claims} <- Token.validate_jwks_token(token) do
      json(conn, %{
        token: token,
        expiresIn: auth_response["expiresIn"],
        expiresAt: auth_response["expiresAt"]
      })
    else
      {:error, :invalid_token} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "invalid_refresh_token"})

      {:error, _reason} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{error: "auth_server_unavailable"})
    end
  end

  def me(conn, _params) do
    user = conn.assigns.current_user

    json(conn, %{
      user: %{
        id: user.id,
        role: user.role
      }
    })
  end

  defp authenticate(conn, username, password) do
    login_module = Application.get_env(:chat, :auth_login_module, Login)

    case login_module.authenticate(username, password) do
      {:ok, user, token, auth_response} ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> json(%{
          user: %{
            id: user.id,
            email: user.email,
            username: user.username,
            matricula: user.matricula,
            codusur: user.codusur,
            filial: user.filial
          },
          token: token,
          expiresIn: auth_response["expiresIn"],
          expiresAt: auth_response["expiresAt"]
        })

      {:error, :invalid_credentials} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "invalid_credentials"})

      {:error, _reason} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{error: "auth_server_unavailable"})
    end
  end
end
