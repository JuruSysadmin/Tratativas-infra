defmodule ChatWeb.HomeLive do
  @moduledoc """
  Página inicial de boas-vindas, desacoplada do chat.

  Renderiza um menu lateral simples com acesso ao `/chat` (que abre em
  uma tela separada) e um conteúdo de boas-vindas.
  """

  use ChatWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end
end
