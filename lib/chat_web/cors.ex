defmodule ChatWeb.Cors do
  @moduledoc "CORS headers for the browser-facing JSON API."

  import Plug.Conn

  @allow_methods "GET, HEAD, PUT, PATCH, POST, DELETE, OPTIONS"
  @allow_headers "accept, authorization, content-type, origin"

  def init(opts), do: opts

  def call(conn, _opts) do
    origin = get_req_header(conn, "origin") |> List.first()

    conn =
      if allowed_origin?(origin) do
        conn
        |> put_resp_header("access-control-allow-origin", origin)
        |> put_resp_header("access-control-allow-credentials", "true")
        |> put_resp_header("access-control-allow-methods", @allow_methods)
        |> put_resp_header("access-control-allow-headers", @allow_headers)
        |> put_resp_header("vary", "origin")
      else
        conn
      end

    if conn.method == "OPTIONS" and allowed_origin?(origin) do
      conn
      |> send_resp(:no_content, "")
      |> halt()
    else
      conn
    end
  end

  defp allowed_origin?(origin) when is_binary(origin) do
    origin in Application.get_env(:chat, :cors_origins, [])
  end

  defp allowed_origin?(_origin), do: false
end
