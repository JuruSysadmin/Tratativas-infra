defmodule ChatWeb.HomeLiveTest do
  use ChatWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Chat.Auth.Identity

  setup %{conn: conn} do
    {:ok, user} = Identity.sync_user(%{"sub" => "home-user"}, %{})
    conn = init_test_session(conn, %{"user_id" => user.id})

    %{conn: conn, user: user}
  end

  test "redirects unauthenticated users to the login page", %{conn: _conn} do
    conn = build_conn()

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/home")
  end

  test "renders hello world with user greeting and navigation to chat", %{
    conn: conn,
    user: user
  } do
    {:ok, view, html} = live(conn, ~p"/home")

    assert html =~ "Hello World!"
    assert html =~ "Bem-vindo, #{user.username}!"
    assert html =~ ~s(href="#main-content")
    assert html =~ ~s(id="main-content")
    assert has_element?(view, ".home-menu-link[href='/chat'][aria-label='Chat']")
    assert has_element?(view, ".home-menu-link[href='/perfil'][aria-label='Perfil']")
  end

  test "renders the brand logo with an accessible name and Carbon-sized mark", %{
    conn: conn
  } do
    {:ok, _view, html} = live(conn, ~p"/home")

    assert html =~ ~s(class="home-brand-logo")
    assert html =~ ~s(alt="Jurunense")

    css = File.read!(Path.expand("../../../assets/css/app.css", __DIR__))

    assert css =~ """
           .home-brand-logo {
             width: auto;
             height: 40px;
           }
           """
  end

  test "renders navigation tiles with labels centered in the main area", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/home")

    assert html =~ ~s(class="home-menu-link")
    assert html =~ ~s(class="home-menu-icon")
    assert html =~ ~s(class="home-menu-label")
    assert html =~ ~s(aria-label="Chat")
    assert html =~ ~s(aria-label="Perfil")

    refute has_element?(view, ".home-main .home-menu-link[aria-label='Vendas']")
    refute has_element?(view, ".home-main .home-menu-link[aria-label='Configurações']")

    assert has_element?(
             view,
             ".home-main .home-menu-link[href='/chat'][aria-label='Chat']",
             "Chat"
           )

    assert has_element?(
             view,
             ".home-main .home-menu-link[href='/perfil'][aria-label='Perfil']",
             "Perfil"
           )

    refute has_element?(view, ".home-topbar .home-menu")

    css = File.read!(Path.expand("../../../assets/css/app.css", __DIR__))

    assert css =~ """
           .home-menu {
             display: flex;
             width: 100%;
             max-width: 480px;
             flex-direction: column;
             gap: 12px;
             margin-top: 32px;
           }
           """

    assert css =~ """
           .home-menu-link {
             display: flex;
             width: 100%;
             min-height: 64px;
             align-items: center;
             justify-content: flex-start;
             gap: 12px;
             padding: 0 16px;
             border: 1px solid var(--cds-border-subtle-01);
             color: var(--cds-text-primary);
             background: var(--cds-layer-01);
             text-decoration: none;
           }
           """

    assert css =~ "@media (min-width: 768px)"
    assert css =~ "width: auto;"
    assert css =~ "max-width: none;"
    assert css =~ "min-width: 128px;"
    assert css =~ "min-height: 88px;"
    assert css =~ "flex-direction: row;"
    assert css =~ "flex-direction: column;"
    assert css =~ "margin-top: 24px;"

    assert css =~ """
           .home-menu-link:hover {
             background: var(--cds-layer-hover-01);
           }
           """

    assert css =~ """
           .home-menu-icon {
             width: 20px;
             height: 20px;
             flex-shrink: 0;
           }
           """

    assert css =~ """
           .home-menu-label {
             font: var(--cds-body-compact-01);
           }
           """
  end

  test "uses a single Carbon icon set for navigation tiles", %{conn: _conn} do
    template =
      File.read!(Path.expand("../../../lib/chat_web/live/home/home_live.html.heex", __DIR__))

    icons =
      File.read!(Path.expand("../../../lib/chat_web/components/core_components.ex", __DIR__))

    assert template =~ ~s(name="carbon-chat")
    refute template =~ "hero-chat-bubble-left-right"
    assert icons =~ ~s(def icon(%{name: "carbon-chat"})
  end

  test "uses Carbon shell tokens for the dark topbar instead of raw hex", %{conn: conn} do
    {:ok, _view, _html} = live(conn, ~p"/home")

    css = File.read!(Path.expand("../../../assets/css/app.css", __DIR__))

    assert css =~ "--cds-shell-header: #001141;"

    assert css =~ """
           .home-topbar {
             display: flex;
             min-height: 56px;
             flex-shrink: 0;
             align-items: center;
             gap: 16px;
             padding: 0 16px;
             border-bottom: 1px solid var(--cds-border-subtle-01);
             color: var(--cds-text-inverse);
             background: var(--cds-shell-header);
           }
           """

    assert css =~ "@media (min-width: 768px)"
    assert css =~ "min-height: 64px;"
    assert css =~ "gap: 24px;"
  end
end
