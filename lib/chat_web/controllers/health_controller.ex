defmodule ChatWeb.HealthController do
  @moduledoc "Health and readiness endpoints for the Chat service."

  use ChatWeb, :controller

  def health(conn, _params) do
    json(conn, %{
      status: "ok",
      version: Application.spec(:chat, :vsn) |> to_string()
    })
  end

  def ready(conn, _params) do
    case Chat.Repo.query("SELECT 1") do
      {:ok, _result} ->
        json(conn, %{status: "ready"})

      {:error, _reason} ->
        not_ready(conn)
    end
  rescue
    DBConnection.ConnectionError ->
      not_ready(conn)
  end

  defp not_ready(conn) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{status: "not_ready", reason: "database_unavailable"})
  end
end
