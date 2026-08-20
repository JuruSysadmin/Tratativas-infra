defmodule ChatWeb.Layouts do
  @moduledoc "Layout components shared by the Chat web interface."

  use ChatWeb, :html

  attr :flash, :map, required: true
  attr :current_scope, :any, default: nil
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div data-app-layout="true">
      <.flash_group flash={@flash} />
      {render_slot(@inner_block)}
    </div>
    """
  end

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="pt-BR" data-carbon-theme="g10">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <title>Chat</title>
        <%= Application.get_env(:live_debugger, :live_debugger_tags) %>
        <script defer phx-track-static type="text/javascript" src={~p"/assets/app.js"}></script>
        <link rel="preconnect" href="https://1.www.s81c.com" />
        <link rel="stylesheet" href="https://1.www.s81c.com/common/carbon/plex/sans.css" />
        <link rel="stylesheet" href={~p"/assets/app.css"} />
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end

  attr :flash, :map, required: true

  def flash_group(assigns) do
    ~H"""
    <div id="flash-group" aria-live="polite">
      <p :if={message = Phoenix.Flash.get(@flash, :info)} class="flash flash-info">{message}</p>
      <div
        :if={message = Phoenix.Flash.get(@flash, :error)}
        class="flash flash-error"
        role="alert"
      >
        <.icon name="carbon-error" class="flash-error-icon" />
        <div>
          <strong>Erro</strong>
          <p>{message}</p>
        </div>
      </div>
    </div>
    """
  end

  attr :message, :string, required: true

  def inline_error_notification(assigns) do
    ~H"""
    <div id="login-error-notification" class="flash flash-error login-inline-error" role="alert">
      <.icon name="carbon-error" class="flash-error-icon" />
      <div>
        <strong>Erro</strong>
        <p>{@message}</p>
      </div>
    </div>
    """
  end
end
