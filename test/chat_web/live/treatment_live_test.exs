defmodule ChatWeb.TreatmentLiveTest do
  use ChatWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Chat.Auth.Identity
  alias Chat.Treatments

  setup %{conn: conn} do
    {:ok, user} = Identity.sync_user(%{"sub" => "treatment-mvp-user"}, %{})
    %{conn: init_test_session(conn, %{"user_id" => user.id}), user: user}
  end

  test "renders one order with its related orders", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/tratativas")

    assert html =~ "Pedidos do cliente 491564"
    assert has_element?(view, "button", "Abrir tratativa")
    assert html =~ "Faturamento"
    assert html =~ ~s(class="delivery-priority-badge")
    assert html =~ ~s(data-priority="Média")
    assert html =~ ~s(class="delivery-priority-label">Prioridade:</span>)
    refute html =~ ~r/class="delivery-priority-badge"[^>]*>\s*Prioridade:/
    assert html =~ "Status da entrega"
    assert html =~ "LIBERADO"
    assert html =~ "Cliente"
    assert html =~ "491564 - LORELEY ANDRADE"
    assert html =~ "Itens do pedido"
    assert html =~ "MASSA ACRILICA 20KG VELOZ BD"
    refute html =~ "Pedidos relacionados"
    refute html =~ "9998043470"
    refute html =~ "TV7"
    refute html =~ "TV8"
    refute has_element?(view, "input[name='room_name']")
  end

  test "redirects unauthenticated users to login", %{conn: _conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(build_conn(), ~p"/tratativas")
  end

  test "renders the treatment protocol and audit timeline", %{conn: conn, user: user} do
    assert {:ok, %{treatment: treatment}} = Treatments.open_for_order(9_998_043_470, user.id)

    {:ok, view, html} = live(conn, ~p"/tratativas/#{treatment.id}")

    assert html =~ Treatments.protocol(treatment)
    assert html =~ "Acompanhamento"
    assert html =~ "treatment_created"
    assert has_element?(view, "a", "Abrir conversa")
  end
end
