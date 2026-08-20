defmodule ChatWeb.MessageFormAccessibilityTest do
  use ChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias ChatWeb.MessageComponents

  test "send button has an accessible name" do
    html =
      render_component(&MessageComponents.message_form/1, %{
        input_text: "",
        mention_suggestions: [],
        room_id: "room-1"
      })

    assert html =~ ~s(aria-label="Enviar mensagem")
    assert html =~ ~s(title="Enviar mensagem")
    assert html =~ ~s(<form id="message-form" phx-hook="MessageOutbox")
    assert html =~ ~s(data-outbox-storage-key="chat:pending:room-1")
    assert html =~ ~s(<textarea)
    assert html =~ ~s(maxlength="4000")
    assert html =~ "Enter envia · Shift+Enter quebra linha"
  end
end
