defmodule ChatWeb.UIShellHeaderTest do
  use ChatWeb.ConnCase, async: true

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Chat.Auth.Identity
  alias ChatWeb.ChatLive
  alias ChatWeb.CoreComponents

  test "renders the accessible Carbon shell landmarks", %{conn: conn} do
    {:ok, user} = Identity.sync_user(%{"sub" => "shell-user"}, %{})

    html =
      conn
      |> init_test_session(%{"user_id" => user.id})
      |> get(~p"/chat")
      |> html_response(200)

    assert html =~ ~s(href="#main-content")
    assert html =~ ~s(class="ui-shell-header")
    assert html =~ ~s(src="/images/Jurunense-BR.svg")
    assert html =~ ~s(aria-label="Pedidos")
    assert html =~ ~s(aria-controls="room-navigation")
    assert html =~ ~s(aria-label="Sair")
    assert html =~ ~s(id="main-content")
    assert html =~ ~s(id="room-navigation")
    assert html =~ ~s(phx-click="open_new_room")
    assert html =~ ~s(phx-click="open_room_explorer")
  end

  test "toggles the mobile navigation state" do
    socket = %Phoenix.LiveView.Socket{} |> assign(%{navigation_open: false})

    assert {:noreply, socket} = ChatLive.handle_event("toggle_navigation", %{}, socket)
    assert socket.assigns.navigation_open
  end

  test "represents a long username with initials and preserves its accessible full name" do
    username = "JOELSON DE BRITO RIBEIRO"

    html =
      render_component(&CoreComponents.ui_shell_header/1,
        username: username,
        navigation_open: false
      )

    assert html =~ ~s(class="ui-shell-account" title="#{username}")
    assert html =~ ~s(class="ui-shell-account-avatar" aria-hidden="true")
    assert html =~ ">JR</span>"
    assert html =~ ~s(<span class="ui-shell-account-name">#{username}</span>)
    refute html =~ ~s(name="carbon-user")
  end

  test "constrains long account names without displacing shell actions" do
    css = File.read!(Path.expand("../../../assets/css/app.css", __DIR__))

    assert css =~ """
           .ui-shell-account-name {
             overflow: hidden;
             text-overflow: ellipsis;
             white-space: nowrap;
           }
           """

    assert css =~ "max-width: min(280px, 35vw)"
    assert css =~ "flex: 0 0 24px"
  end
end
