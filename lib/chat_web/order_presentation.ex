defmodule ChatWeb.OrderPresentation do
  @moduledoc """
  Apresentação de pedidos para usuários finais.

  Os códigos TV7/TV8 pertencem ao ERP e não fazem parte da linguagem da interface.
  """

  def type_label("TV7 - " <> label), do: label
  def type_label("TV8 - " <> label), do: label
  def type_label(type) when is_binary(type), do: type
  def type_label(_type), do: "Pedido"
end
