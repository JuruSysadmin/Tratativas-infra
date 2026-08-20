defmodule ChatWeb.CarbonFluidStylesTest do
  use ExUnit.Case, async: true

  @chat_path Path.expand("../../lib/chat_web/live/components/room_modal_component.ex", __DIR__)
  @css_path Path.expand("../../assets/css/app.css", __DIR__)
  @login_path Path.expand("../../lib/chat_web/live/login_live.html.heex", __DIR__)

  test "uses fluid forms and actions only in contained simple flows" do
    login = File.read!(@login_path)
    chat = File.read!(@chat_path)

    assert login =~ ~s(class="fluid-form login-fluid-form")
    assert login =~ ~s(class="fluid-actions login-fluid-actions")
    assert chat =~ ~s(class="fluid-form room-create-form")
    assert chat =~ ~s(class="carbon-modal-footer fluid-actions")
    refute chat =~ ~s(id="message-form" class="fluid-form")
  end

  test "defines the Carbon fluid sizing, attachment and accessible dividers" do
    css = File.read!(@css_path)

    assert css =~ ".fluid-form"
    assert css =~ "height: 64px"
    assert css =~ "margin-bottom: 0"
    assert css =~ ".fluid-actions"
    assert css =~ "grid-template-columns: repeat(2, minmax(0, 1fr))"
    assert css =~ "border-right: 1px solid var(--cds-border-inverse)"
  end
end
