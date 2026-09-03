defmodule Chat.Orders.CustomerNamesTest do
  use ExUnit.Case, async: false

  alias Chat.Orders.CustomerNames

  setup do
    Application.put_env(:chat, :orders_api,
      base_url: "http://orders.test",
      request_options: [plug: {Req.Test, __MODULE__}]
    )

    Application.put_env(:chat, :orders_customer_names_ttl_ms, 60)

    on_exit(fn ->
      Application.delete_env(:chat, :orders_api)
      Application.delete_env(:chat, :orders_customer_names_ttl_ms)
    end)

    :ok
  end

  test "resolve nomes, cacheia pedidos frescos e ignora falhas individuais" do
    {:ok, counter} = Agent.start_link(fn -> %{} end)

    Req.Test.stub(__MODULE__, fn conn ->
      %{"orderId" => order_id} = Plug.Conn.fetch_query_params(conn).query_params
      Agent.update(counter, fn counts -> Map.update(counts, order_id, 1, &(&1 + 1)) end)

      body =
        if order_id == "12" do
          %{"items" => []}
        else
          %{
            "items" => [
              %{
                "orderId" => String.to_integer(order_id),
                "customerId" => 1,
                "customerName" => "Cliente #{order_id}"
              }
            ]
          }
        end

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(body))
    end)

    assert %{11 => "Cliente 11"} = CustomerNames.resolve([11], "Bearer token")
    assert %{} == CustomerNames.resolve(12, "Bearer token")
    assert %{} == CustomerNames.resolve(13, nil)

    assert %{11 => "Cliente 11"} = CustomerNames.resolve([11, 13], "Bearer token")

    counts = Agent.get(counter, & &1)
    assert counts["11"] == 1
    assert counts["13"] == 1
  end

  test "expira a entrada após o TTL e busca novamente" do
    {:ok, counter} = Agent.start_link(fn -> %{} end)

    Req.Test.stub(__MODULE__, fn conn ->
      %{"orderId" => order_id} = Plug.Conn.fetch_query_params(conn).query_params
      Agent.update(counter, fn counts -> Map.update(counts, order_id, 1, &(&1 + 1)) end)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{
          "items" => [
            %{
              "orderId" => String.to_integer(order_id),
              "customerId" => 2,
              "customerName" => "Cliente TTL"
            }
          ]
        })
      )
    end)

    assert %{21 => "Cliente TTL"} = CustomerNames.resolve([21], "Bearer token")
    assert %{21 => "Cliente TTL"} = CustomerNames.resolve([21], "Bearer token")
    Process.sleep(70)
    assert %{21 => "Cliente TTL"} = CustomerNames.resolve([21], "Bearer token")

    assert Agent.get(counter, & &1)["21"] == 2
  end

  test "falha de conexão não derruba a resolução" do
    Application.put_env(:chat, :orders_api,
      base_url: "http://127.0.0.1:1",
      request_options: [retry: false]
    )

    assert %{} == CustomerNames.resolve([31], "Bearer token")
  end
end
