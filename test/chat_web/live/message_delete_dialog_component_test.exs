defmodule ChatWeb.MessageDeleteDialogComponentTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias ChatWeb.MessageDeleteDialogComponent

  test "renders an accessible confirmation dialog for the selected message" do
    html =
      render_component(&MessageDeleteDialogComponent.message_delete_dialog/1,
        message_id: "f8e1c254-9102-4205-a1df-9609f456abcd"
      )

    assert html =~ ~s(role="dialog")
    assert html =~ ~s(aria-modal="true")
    assert html =~ "Excluir esta mensagem para todos os participantes?"
    assert html =~ ~s(phx-click="cancel_delete_message")
    assert html =~ ~s(phx-click="delete_message")
    assert html =~ ~s(phx-value-message_id="f8e1c254-9102-4205-a1df-9609f456abcd")
  end

  test "renders nothing without a message awaiting confirmation" do
    assert render_component(&MessageDeleteDialogComponent.message_delete_dialog/1,
             message_id: nil
           ) == ""
  end
end
