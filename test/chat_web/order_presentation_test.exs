defmodule ChatWeb.OrderPresentationTest do
  use ExUnit.Case, async: true

  alias ChatWeb.OrderPresentation

  test "removes ERP prefixes from order type labels" do
    assert OrderPresentation.type_label("TV7 - Faturamento") == "Faturamento"
    assert OrderPresentation.type_label("TV8 - Entrega (EN)") == "Entrega (EN)"
  end

  test "preserves unknown user-facing order type labels" do
    assert OrderPresentation.type_label("Cancelado") == "Cancelado"
    assert OrderPresentation.type_label(nil) == "Pedido"
  end
end
