defmodule ChatWeb.ProfileLive do
  @moduledoc """
  Página do usuário logado (perfil).

  Renderiza os dados do usuário corrente, sincronizados da Identity local
  (originados dos claims do JWT no momento do login).
  """

  use ChatWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end
end
