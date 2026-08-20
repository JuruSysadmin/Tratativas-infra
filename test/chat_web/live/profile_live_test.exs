defmodule ChatWeb.ProfileLiveTest do
  use ChatWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Chat.Auth.Identity

  setup %{conn: conn} do
    {:ok, user} =
      Identity.sync_user(
        %{
          "sub" => "profile-user",
          "email" => "profile@jurunense.com",
          "username" => "profile-user",
          "matricula" => "M12345",
          "codusur" => "RCA007",
          "filial" => "2"
        },
        %{}
      )

    conn = init_test_session(conn, %{"user_id" => user.id})

    %{conn: conn, user: user}
  end

  test "redirects unauthenticated users to the login page", %{conn: _conn} do
    conn = build_conn()

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/perfil")
  end

  test "renders the profile page with the current user data", %{conn: conn, user: user} do
    {:ok, view, html} = live(conn, ~p"/perfil")

    assert html =~ "Meu perfil"
    assert has_element?(view, ".profile-row", "Usuário")
    assert has_element?(view, ".profile-value", user.username)
    assert has_element?(view, ".profile-value", user.email)
    assert has_element?(view, ".profile-value", user.matricula)
    assert has_element?(view, ".profile-value", user.codusur)
    assert has_element?(view, ".profile-value", user.filial)
  end

  test "reuses the home topbar with the brand logo and skip link", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/perfil")

    assert html =~ ~s(href="#main-content")
    assert has_element?(view, ".home-topbar .home-brand .home-brand-logo[alt='Jurunense']")
    refute has_element?(view, ".home-topbar .home-menu")
  end
end
