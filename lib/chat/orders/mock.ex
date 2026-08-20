defmodule Chat.Orders.Mock do
  @moduledoc """
  Local order fixture used by the treatment MVP.

  This module is intentionally isolated so the real Orders API can replace it
  without changing the room or LiveView contracts.
  """

  @orders [
    %{
      order_id: 9_998_043_470,
      parent_order_id: 9_998_043_469,
      customer_id: 491_564,
      customer_name: "491564 - LORELEY ANDRADE",
      order_type: "TV8 - Entrega (EN)",
      status: "LIBERADO",
      amount: 109.99,
      delivery_priority: "Média",
      delivery_date: "2026-08-24",
      items: [
        %{
          description: "MASSA ACRILICA 20KG VELOZ BD",
          quantity: 1,
          total: 109.99,
          delivery_type: "ENTREGA",
          weight: 20.5,
          department: "TINTAS E ACESSORIOS",
          brand: "VELOZ"
        }
      ],
      delivery: %{
        place: "19 - E-COMMERCE",
        city: "BELEM",
        state: "PA",
        carrier: "Entrega Jurunense",
        estimated_date: "2026-08-24"
      }
    },
    %{
      order_id: 9_998_043_469,
      parent_order_id: nil,
      customer_id: 491_564,
      customer_name: "491564 - LORELEY ANDRADE",
      order_type: "TV7 - Faturamento",
      status: "FATURADO",
      amount: 109.99,
      delivery_date: "2026-08-18",
      delivery_priority: "-",
      items: [
        %{
          description: "MASSA ACRILICA 20KG VELOZ BD",
          quantity: 1,
          total: 109.99,
          delivery_type: "ENTREGA",
          weight: 20.5,
          department: "TINTAS E ACESSORIOS",
          brand: "VELOZ"
        }
      ],
      delivery: %{
        place: "19 - E-COMMERCE",
        city: "BELEM",
        state: "PA",
        carrier: "Entrega Jurunense",
        estimated_date: "2026-08-24"
      }
    }
  ]

  def list_for_customer(customer_id) when is_integer(customer_id) do
    Enum.filter(@orders, &(&1.customer_id == customer_id))
  end

  def list_treatments_for_customer(customer_id) when is_integer(customer_id) do
    customer_id
    |> list_for_customer()
    |> Enum.group_by(&(Map.get(&1, :parent_order_id) || &1.order_id))
    |> Enum.filter(fn {_parent_order_id, orders} ->
      Enum.any?(orders, &String.starts_with?(&1.order_type, "TV7"))
    end)
    |> Enum.map(fn {parent_order_id, orders} ->
      deliveries = Enum.filter(orders, &String.starts_with?(&1.order_type, "TV8"))

      %{
        order: Enum.find(orders, &String.starts_with?(&1.order_type, "TV7")),
        delivery: Enum.at(deliveries, 0),
        deliveries: deliveries,
        order_id: parent_order_id
      }
    end)
  end

  def get(order_id) when is_integer(order_id) do
    case Enum.find(@orders, &(&1.order_id == order_id)) do
      %{order_type: "TV7" <> _} = order ->
        Map.put(order, :related_deliveries, list_related_deliveries(order_id))

      order ->
        order
    end
  end

  def get(_order_id), do: nil

  defp list_related_deliveries(parent_order_id) do
    Enum.filter(@orders, &(Map.get(&1, :parent_order_id) == parent_order_id))
  end
end
