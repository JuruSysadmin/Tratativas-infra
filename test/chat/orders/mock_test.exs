defmodule Chat.Orders.MockTest do
  use ExUnit.Case, async: true

  alias Chat.Orders.Mock

  test "returns the fixture customer with TV7 and TV8 orders" do
    orders = Mock.list_for_customer(491_564)

    assert [%{order_type: "TV8 - Entrega (EN)"}, %{order_type: "TV7 - Faturamento"}] = orders
  end

  test "returns the order context by order id" do
    assert %{order_id: 9_998_043_469, status: "FATURADO", related_deliveries: deliveries} =
             Mock.get(9_998_043_469)

    assert [%{order_id: 9_998_043_470, order_type: "TV8 - Entrega (EN)"}] = deliveries
  end

  test "groups TV8 deliveries under the TV7 treatment" do
    assert [%{order_id: 9_998_043_469, deliveries: [%{order_id: 9_998_043_470}]}] =
             Mock.list_treatments_for_customer(491_564)
  end

  test "returns nil for an unknown order" do
    assert Mock.get(0) == nil
  end
end
