defmodule ChatWeb.CarbonThemeTest do
  use ExUnit.Case, async: true

  @css_path Path.expand("../../assets/css/app.css", __DIR__)

  test "defines the semantic Carbon Gray 10 theme contract" do
    css = File.read!(@css_path)

    assert css =~ ~s(data-carbon-theme="g10")
    assert css =~ "--cds-background: #f4f4f4"
    assert css =~ "--cds-layer-01: #ffffff"
    assert css =~ "--cds-text-primary: #161616"
    assert css =~ "--cds-interactive: #0f62fe"
    assert css =~ "--cds-focus: #0f62fe"
    assert css =~ ":focus-visible"
    assert css =~ ":active"
    assert css =~ ":disabled"
  end

  test "defines and loads the Carbon productive typography" do
    css = File.read!(@css_path)
    layouts = File.read!(Path.expand("../../lib/chat_web/components/layouts.ex", __DIR__))

    assert layouts =~ "https://1.www.s81c.com/common/carbon/plex/sans.css"
    assert css =~ "--cds-body-compact-01-font-size: 0.875rem"
    assert css =~ "--cds-body-compact-01-line-height: 1.125rem"
    assert css =~ "--cds-heading-compact-01-font-weight: 600"
    assert css =~ "--cds-label-01-font-size: 0.75rem"
    assert css =~ "font: var(--cds-body-compact-01)"
  end
end
