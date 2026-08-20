defmodule Chat.Auth.Plug do
  @moduledoc """
  Authentication plug for external RS256/JWKS bearer tokens.
  """

  import Plug.Conn

  alias Chat.Auth.Authenticator

  def init(opts), do: opts

  def call(conn, opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> authenticate(conn, token, opts)
      _headers -> unauthorized(conn, "Token ausente")
    end
  end

  defp authenticate(conn, token, opts) do
    authenticator = Application.get_env(:chat, :authenticator_module, Authenticator)

    case authenticator.authenticate(token, opts) do
      {:ok, user, claims} ->
        conn
        |> assign(:current_user, user)
        |> assign(:user_claims, claims)

      {:error, _reason} ->
        unauthorized(conn, "Token inválido")
    end
  end

  defp unauthorized(conn, message) do
    conn
    |> put_status(:unauthorized)
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{message: message}))
    |> halt()
  end
end
