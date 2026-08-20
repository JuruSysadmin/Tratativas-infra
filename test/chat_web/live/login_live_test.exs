defmodule ChatWeb.LoginLiveTest do
  use ChatWeb.ConnCase, async: true

  test "renders inside the application layout with reusable form inputs", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ ~s(data-app-layout="true")
    assert html =~ ~s(data-input-component="true")
  end

  test "renders an accessible login landmark and focuses the username", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ ~s(<main class="login-container" aria-labelledby="login-title">)
    assert html =~ ~s(<h1 id="login-title">Entrar</h1>)
    assert html =~ ~s(name="username")
    assert html =~ ~s(autocomplete="username")
    assert html =~ ~s(autofocus)
    assert html =~ ~s(autocomplete="current-password")
  end

  test "renders the current application version in the login footer", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)
    version = Application.spec(:chat, :vsn) |> to_string()

    assert html =~ ~s(<footer class="login-footer" data-app-version="#{version}">)
    assert html =~ "Versão #{version}"
  end

  test "shows one inline notification after an authentication failure", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{})
      |> fetch_flash()
      |> put_flash(:login_username, "alice")
      |> put_flash(:error, "Usuário ou senha incorretos. Tente novamente.")

    html = conn |> get(~p"/") |> html_response(200)

    assert [_, _] = String.split(html, "Usuário ou senha incorretos. Tente novamente.")
    assert [_, _] = String.split(html, ~s(id="login-error-notification"))
    assert html =~ ~s(id="login-error-notification")
    assert html =~ ~s(role="alert")
    assert html =~ "Usuário ou senha incorretos. Tente novamente."
    refute html =~ ~s(id="username-error")
    refute html =~ ~s(id="password-error")
    assert html =~ ~s(name="username")
    assert html =~ ~s(value="alice")
    assert html =~ ~s(name="password")
    refute html =~ ~s(value="secret")
  end
end
