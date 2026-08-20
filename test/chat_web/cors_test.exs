defmodule ChatWeb.CorsTest do
  use ChatWeb.ConnCase, async: false

  test "answers the local frontend preflight request", %{conn: conn} do
    conn =
      conn
      |> put_req_header("origin", "https://vm.jurunense.com")
      |> options("/api/order-conversations")

    assert response(conn, 204) == ""
    assert get_resp_header(conn, "access-control-allow-origin") == ["https://vm.jurunense.com"]
    assert get_resp_header(conn, "access-control-allow-credentials") == ["true"]
  end

  test "does not allow an unknown origin", %{conn: conn} do
    conn =
      conn
      |> put_req_header("origin", "http://localhost:9999")
      |> options("/api/order-conversations")

    refute get_resp_header(conn, "access-control-allow-origin") == ["http://localhost:9999"]
  end
end
