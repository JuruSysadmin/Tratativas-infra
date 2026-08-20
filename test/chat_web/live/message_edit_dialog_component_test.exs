defmodule ChatWeb.MessageEditDialogComponentTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias ChatWeb.MessageEditDialogComponent

  test "renders an accessible edit dialog with the current content" do
    html =
      render_component(&MessageEditDialogComponent.message_edit_dialog/1,
        message_id: "f8e1c254-9102-4205-a1df-9609f456abcd",
        content: "Conteúdo atual"
      )

    assert html =~ ~s(role="dialog")
    assert html =~ ~s(aria-modal="true")
    assert html =~ "Editar mensagem"
    assert html =~ ~s(id="message-edit-form")
    assert html =~ ~s(phx-submit="save_edit_message")
    assert html =~ ~s(id="message-edit-input")
    assert html =~ "Conteúdo atual"
    assert html =~ ~s(phx-click="cancel_edit_message")
    assert html =~ ~s(name="message_id")
    assert html =~ ~s(value="f8e1c254-9102-4205-a1df-9609f456abcd")
    assert html =~ ~s(type="submit")
    assert html =~ ~s(phx-click-away="cancel_edit_message")
  end

  test "renders nothing without a message being edited" do
    assert render_component(&MessageEditDialogComponent.message_edit_dialog/1,
             message_id: nil
           ) == ""
  end
end
