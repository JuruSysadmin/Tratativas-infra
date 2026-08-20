defmodule ChatWeb.HealthControllerTest do
  use ChatWeb.ConnCase, async: true

  describe "GET /health" do
    test "returns liveness status and application version", %{conn: conn} do
      conn = get(conn, "/health")

      assert %{"status" => "ok", "version" => version} = json_response(conn, 200)
      assert version == Application.spec(:chat, :vsn) |> to_string()
    end
  end

  describe "GET /ready" do
    test "returns readiness status when the database is available", %{conn: conn} do
      conn = get(conn, "/ready")

      assert %{"status" => "ready"} = json_response(conn, 200)
    end
  end
end
