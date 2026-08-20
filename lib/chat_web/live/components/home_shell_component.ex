defmodule ChatWeb.HomeShellComponent do
  @moduledoc """
  Shell compartilhado pelas páginas do grupo home (home e perfil).

  Hoje expõe apenas a topbar com a marca; o restante da página fica no
  template de cada LiveView.
  """

  use Phoenix.Component

  attr :class, :string, default: nil

  def topbar(assigns) do
    ~H"""
    <header class={["home-topbar", @class]}>
      <div class="home-brand">
        <img src="/images/Jurunense-BR.svg" alt="Jurunense" class="home-brand-logo" />
      </div>
    </header>
    """
  end
end
