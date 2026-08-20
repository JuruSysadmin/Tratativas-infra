defmodule ChatWeb.CarbonErrorStatesTest do
  use ChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias ChatWeb.CoreComponents
  alias ChatWeb.Layouts

  test "input invalid state has border-independent semantics, icon and message" do
    html =
      render_component(&CoreComponents.input/1, %{
        name: "username",
        label: "Usuário",
        error: "Informe o usuário"
      })

    assert html =~ ~s(aria-invalid="true")
    assert html =~ ~s(aria-describedby="username-error")
    assert html =~ ~s(id="username-error")
    assert html =~ "Informe o usuário"
    assert html =~ "input-error-icon"
  end

  test "error flash is an assertive Carbon notification with an icon" do
    html = render_component(&Layouts.flash_group/1, %{flash: %{"error" => "Falha externa"}})

    assert html =~ ~s(role="alert")
    assert html =~ "flash-error-icon"
    assert html =~ "Falha externa"
  end

  test "error tokens and message failure use more than red alone" do
    css = File.read!(Path.expand("../../assets/css/app.css", __DIR__))

    chat =
      File.read!(Path.expand("../../lib/chat_web/live/components/message_components.ex", __DIR__))

    assert css =~ "--cds-text-error: #da1e28"
    assert css =~ "--cds-support-error-inverse: #fa4d56"
    assert css =~ "--cds-notification-error-background: #fff1f1"
    assert css =~ ".form-group--invalid input"
    assert chat =~ ~s(<.icon name="carbon-error" class="message-error-icon" />)
  end
end
