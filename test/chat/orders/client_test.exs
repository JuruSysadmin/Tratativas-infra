defmodule Chat.Orders.ClientTest do
  use ExUnit.Case, async: false

  alias Chat.Orders.Client

  setup do
    Application.put_env(:chat, :orders_api,
      base_url: "http://orders.test",
      request_options: [plug: {Req.Test, __MODULE__}]
    )

    on_exit(fn -> Application.delete_env(:chat, :orders_api) end)
    :ok
  end

  test "busca o pedido e encaminha o bearer token" do
    Req.Test.stub(__MODULE__, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/orders"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer jwt-token"]

      assert Plug.Conn.fetch_query_params(conn).query_params == %{"orderId" => "123"}

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{
          "items" => [%{"orderId" => 123, "customerId" => 456, "customerName" => "João Silva"}]
        })
      )
    end)

    assert {:ok, %{customer_id: 456, customer_name: "João Silva"}} =
             Client.get(123, "Bearer jwt-token")
  end

  test "retorna pedido não encontrado quando a API não retorna itens" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{"items" => []}))
    end)

    assert {:error, :not_found} = Client.get(123, "Bearer jwt-token")
  end

  test "resolve vários pedidos e descarta falhas individuais" do
    Req.Test.stub(__MODULE__, fn conn ->
      %{"orderId" => order_id} = Plug.Conn.fetch_query_params(conn).query_params

      if order_id == "3" do
        Plug.Conn.send_resp(conn, 404, "not found")
      else
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "items" => [
              %{
                "orderId" => String.to_integer(order_id),
                "customerId" => 456,
                "customerName" => "Cliente #{order_id}"
              }
            ]
          })
        )
      end
    end)

    assert %{
             1 => %{customer_name: "Cliente 1"},
             2 => %{customer_name: "Cliente 2"}
           } = Client.get_many([1, 2, 3], "Bearer jwt-token")
  end
end
