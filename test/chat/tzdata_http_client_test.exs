defmodule Chat.TzdataHTTPClientTest do
  use ExUnit.Case, async: false

  alias Chat.TzdataHTTPClient

  test "returns status, headers, and body for GET requests" do
    Req.Test.stub(__MODULE__, fn conn ->
      Plug.Conn.send_resp(conn, 200, "tzdata payload")
    end)

    Application.put_env(:chat, :tzdata_http_client_options, plug: {Req.Test, __MODULE__})

    on_exit(fn -> Application.delete_env(:chat, :tzdata_http_client_options) end)

    assert {:ok, {200, headers, "tzdata payload"}} =
             TzdataHTTPClient.get("https://tzdata.test/latest", [], follow_redirect: true)

    assert is_list(headers)
  end

  test "returns status and headers for HEAD requests" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("etag", "tzdata-version")
      |> Plug.Conn.send_resp(200, "")
    end)

    Application.put_env(:chat, :tzdata_http_client_options, plug: {Req.Test, __MODULE__})

    on_exit(fn -> Application.delete_env(:chat, :tzdata_http_client_options) end)

    assert {:ok, {200, headers}} =
             TzdataHTTPClient.head("https://tzdata.test/latest", [], follow_redirect: true)

    assert {"etag", "tzdata-version"} in headers
  end
end
