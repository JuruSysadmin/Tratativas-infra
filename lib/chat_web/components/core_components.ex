defmodule ChatWeb.CoreComponents do
  @moduledoc false

  use Phoenix.Component

  attr :id, :string, default: nil
  attr :name, :string, required: true
  attr :label, :string, default: nil
  attr :type, :string, default: "text"
  attr :value, :any, default: nil
  attr :class, :string, default: nil
  attr :error, :string, default: nil
  attr :rest, :global, include: ~w(autocomplete disabled maxlength placeholder required rows)

  def input(assigns) do
    ~H"""
    <div class={["form-group", @error && "form-group--invalid"]} data-input-component="true">
      <label :if={@label} for={@id || @name}>{@label}</label>
      <%= if @type == "textarea" do %>
        <textarea
          id={@id || @name}
          name={@name}
          class={@class}
          aria-invalid={to_string(not is_nil(@error))}
          aria-describedby={@error && "#{@id || @name}-error"}
          {@rest}
        ><%= @value %></textarea>
      <% else %>
        <input
          type={@type}
          id={@id || @name}
          name={@name}
          value={@value}
          class={@class}
          aria-invalid={to_string(not is_nil(@error))}
          aria-describedby={@error && "#{@id || @name}-error"}
          {@rest}
        />
      <% end %>
      <.icon :if={@error} name="carbon-error" class="input-error-icon" />
      <p :if={@error} id={"#{@id || @name}-error"} class="input-error-message">
        {@error}
      </p>
    </div>
    """
  end

  attr :username, :string, required: true
  attr :navigation_open, :boolean, required: true
  attr :notification_count, :integer, default: 0
  attr :notification_panel_open, :boolean, default: false

  def ui_shell_header(assigns) do
    notification_label =
      case assigns.notification_count do
        0 -> "Notificações, nenhuma não lida"
        1 -> "Notificações, 1 não lida"
        count -> "Notificações, #{count} não lidas"
      end

    assigns =
      assigns
      |> assign(:notification_label, notification_label)
      |> assign(:account_initials, account_initials(assigns.username))

    ~H"""
    <a class="skip-to-content" href="#main-content">Pular para o conteúdo principal</a>
    <header class="ui-shell-header">
      <button
        type="button"
        class="ui-shell-header-action ui-shell-menu-button"
        phx-click="toggle_navigation"
        aria-label="Alternar navegação de salas"
        aria-controls="room-navigation"
        aria-expanded={to_string(@navigation_open)}
      >
        <.icon name="carbon-menu" />
      </button>

      <a class="ui-shell-name" href="/chat" aria-label="Jurunense" title="Jurunense">
        <img src="/images/Jurunense-BR.svg" alt="Jurunense" class="ui-shell-logo" />
      </a>

      <nav class="ui-shell-utilities" aria-label="Utilidades globais">
        <.link
          class="ui-shell-header-action"
          href="/tratativas"
          aria-label="Pedidos"
          title="Pedidos"
        >
          Pedidos
        </.link>
        <button
          id="notification-toggle"
          type="button"
          class="ui-shell-header-action ui-shell-notification-action"
          phx-click="toggle_notification_panel"
          aria-label={@notification_label}
          aria-controls="notification-panel"
          aria-expanded={to_string(@notification_panel_open)}
          title="Notificações"
        >
          <.icon name="carbon-notification" />
          <span :if={@notification_count > 0} id="notification-badge" class="notification-badge">
            {@notification_count}
          </span>
        </button>
        <div class="ui-shell-account" title={@username}>
          <span class="ui-shell-account-avatar" aria-hidden="true">{@account_initials}</span>
          <span class="ui-shell-account-name">{@username}</span>
        </div>
        <.link
          class="ui-shell-header-action"
          href="/session"
          method="delete"
          aria-label="Sair"
          title="Sair"
        >
          <.icon name="carbon-logout" />
        </.link>
      </nav>
    </header>
    """
  end

  defp account_initials(username) do
    username
    |> String.split()
    |> initials_from_words()
    |> String.upcase()
  end

  defp initials_from_words([]), do: "?"

  defp initials_from_words([word]) do
    word
    |> String.graphemes()
    |> Enum.take(2)
    |> Enum.join()
  end

  defp initials_from_words([first | rest]) do
    first_grapheme(first) <> first_grapheme(List.last(rest))
  end

  defp first_grapheme(word), do: String.first(word) || ""

  attr :name, :string, required: true
  attr :class, :string, default: nil

  def icon(%{name: "hero-chat-bubble-left-right"} = assigns) do
    ~H"""
    <svg
      class={@class}
      aria-hidden="true"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.5"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M8.625 12h.008m3.742 0h.008m3.742 0h.008M21 12c0 4.556-4.03 8.25-9 8.25a9.76 9.76 0 0 1-2.555-.337A5.97 5.97 0 0 1 5.41 20.97a5.97 5.97 0 0 1-.474-.065 4.48 4.48 0 0 0 .978-2.025c.09-.457-.133-.901-.467-1.226C3.93 16.178 3 14.189 3 12c0-4.556 4.03-8.25 9-8.25s9 3.694 9 8.25Z"
      />
    </svg>
    """
  end

  def icon(%{name: "carbon-menu"} = assigns) do
    ~H"""
    <svg class={@class} aria-hidden="true" viewBox="0 0 32 32" fill="currentColor">
      <path d="M4 7h24v2H4zm0 8h24v2H4zm0 8h24v2H4z" />
    </svg>
    """
  end

  def icon(%{name: "carbon-overflow-menu-vertical"} = assigns) do
    ~H"""
    <svg class={@class} aria-hidden="true" viewBox="0 0 32 32" fill="currentColor">
      <circle cx="16" cy="8" r="2" />
      <circle cx="16" cy="16" r="2" />
      <circle cx="16" cy="24" r="2" />
    </svg>
    """
  end

  def icon(%{name: "carbon-user"} = assigns) do
    ~H"""
    <svg class={@class} aria-hidden="true" viewBox="0 0 32 32" fill="currentColor">
      <path d="M16 16a7 7 0 1 0-7-7 7 7 0 0 0 7 7Zm0-12a5 5 0 1 1-5 5 5 5 0 0 1 5-5Zm0 14c-7.2 0-13 4-13 9v1h2v-1c0-3.8 4.9-7 11-7s11 3.2 11 7v1h2v-1c0-5-5.8-9-13-9Z" />
    </svg>
    """
  end

  def icon(%{name: "carbon-notification"} = assigns) do
    ~H"""
    <svg class={@class} aria-hidden="true" viewBox="0 0 32 32" fill="currentColor">
      <path d="M28.7 25.3 26 22.6V15a10 10 0 0 0-9-9.9V2h-2v3.1A10 10 0 0 0 6 15v7.6l-2.7 2.7A1 1 0 0 0 4 27h8a4 4 0 0 0 8 0h8a1 1 0 0 0 .7-1.7ZM16 29a2 2 0 0 1-2-2h4a2 2 0 0 1-2 2ZM6.4 25 8 23.4V15a8 8 0 0 1 16 0v8.4l1.6 1.6Z" />
    </svg>
    """
  end

  def icon(%{name: "carbon-logout"} = assigns) do
    ~H"""
    <svg class={@class} aria-hidden="true" viewBox="0 0 32 32" fill="currentColor">
      <path d="m23 6-1.4 1.4 7.6 7.6H12v2h17.2l-7.6 7.6L23 26l10-10ZM4 4h12v2H4v20h12v2H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2Z" />
    </svg>
    """
  end

  def icon(%{name: "carbon-add"} = assigns) do
    ~H"""
    <svg class={@class} aria-hidden="true" viewBox="0 0 32 32" fill="currentColor">
      <path d="M17 15V6h-2v9H6v2h9v9h2v-9h9v-2z" />
    </svg>
    """
  end

  def icon(%{name: "carbon-ibm-watsonx-assistant"} = assigns) do
    ~H"""
    <svg class={@class} aria-hidden="true" viewBox="0 0 32 32" fill="currentColor">
      <path d="M28 2h-10c-1.1035 0-2 .8965-2 2v6c0 1.1035.8965 2 2 2h2.4229l1.7314 3 1.7324-1-2.3096-4H18V4h10v6h-3v2h3c1.1035 0 2-.8965 2-2V4c0-1.1035-.8965-2-2-2ZM14.6904 31l-1.7324-1 3.4648-6H22c1.1046 0 2-.8954 2-2v-5h2v5c0 2.2091-1.7909 4-4 4h-4.4229l-2.8867 5Z" />
      <circle cx="10" cy="17" r="1" />
      <circle cx="14" cy="17" r="1" />
      <circle cx="18" cy="17" r="1" />
      <path d="M12 26H6c-2.2091 0-4-1.7909-4-4V12c0-2.2091 1.7909-4 4-4h8v2H6c-1.1046 0-2 .8954-2 2v10c0 1.1046.8954 2 2 2h6Z" />
    </svg>
    """
  end

  def icon(%{name: "carbon-search"} = assigns) do
    ~H"""
    <svg class={@class} aria-hidden="true" viewBox="0 0 32 32" fill="currentColor">
      <path d="m29 27.6-7.6-7.6a10 10 0 1 0-1.4 1.4l7.6 7.6ZM4 14a10 10 0 1 1 10 10A10 10 0 0 1 4 14Z" />
    </svg>
    """
  end

  def icon(%{name: "carbon-pin"} = assigns) do
    ~H"""
    <svg class={@class} aria-hidden="true" viewBox="0 0 32 32" fill="currentColor">
      <path d="m28.7 14.3-11-11a1 1 0 0 0-1.4 0l-2 2a1 1 0 0 0 0 1.4l1.6 1.6-6.2 6.2-2-2-1.4 1.4 4.6 4.6L3 26.4 4.6 28l7.9-7.9 4.6 4.6 1.4-1.4-2-2 6.2-6.2 1.6 1.6a1 1 0 0 0 1.4 0l2-2a1 1 0 0 0 0-1.4Zm-11.6 4.8-5.2-5.2 5.4-5.4 5.2 5.2Z" />
    </svg>
    """
  end

  def icon(%{name: "carbon-trash"} = assigns) do
    ~H"""
    <svg class={@class} aria-hidden="true" viewBox="0 0 32 32" fill="currentColor" width="20" height="20">
      <path d="M12 12h2v12h-2zm6 0h2v12h-2z" />
      <path d="M4 6v2h2v20a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V8h2V6Zm4 22V8h16v20Zm4-26h8v2h-8z" />
    </svg>
    """
  end

  def icon(%{name: "carbon-edit"} = assigns) do
    ~H"""
    <svg class={@class} aria-hidden="true" viewBox="0 0 32 32" fill="currentColor" width="20" height="20">
      <path d="M2 26h28v2H2z" />
      <path d="M25.4 9c.8-.8.8-2 0-2.8 0 0 0 0 0 0l-3.6-3.6c-.8-.8-2-.8-2.8 0 0 0 0 0 0l-15 15V24h6.4L25.4 9zM20.4 4 24 7.6l-3 3L17.4 7 20.4 4zM6 24v-3.6l10-10 3.6 3.6-10 10H6z" />
    </svg>
    """
  end

  def icon(%{name: "carbon-close"} = assigns) do
    ~H"""
    <svg class={@class} aria-hidden="true" viewBox="0 0 32 32" fill="currentColor">
      <path d="m24.6 9-1.4-1.4-7.2 7.2-7.2-7.2L7.4 9l7.2 7.2-7.2 7.2 1.4 1.4 7.2-7.2 7.2 7.2 1.4-1.4-7.2-7.2z" />
    </svg>
    """
  end

  def icon(%{name: "carbon-error"} = assigns) do
    ~H"""
    <svg class={@class} aria-hidden="true" viewBox="0 0 32 32" fill="currentColor">
      <path d="M16 2a14 14 0 1 0 14 14A14 14 0 0 0 16 2Zm0 26a12 12 0 1 1 12-12 12 12 0 0 1-12 12Z" />
      <path d="M15 8h2v11h-2zm0 14h2v2h-2z" />
    </svg>
    """
  end

  def icon(%{name: "carbon-send-filled"} = assigns) do
    ~H"""
    <svg class={@class} aria-hidden="true" viewBox="0 0 32 32" fill="currentColor" width="20" height="20">
      <path d="M27.45 15.11l-22-11a1 1 0 00-1.08.12 1 1 0 00-.33 1L6.69 15H18v2H6.69L4 26.74A1 1 0 005 28a1 1 0 00.45-.11l22-11a1 1 0 000-1.78z" />
    </svg>
    """
  end

  def icon(%{name: "carbon-home"} = assigns) do
    ~H"""
    <svg class={@class} aria-hidden="true" viewBox="0 0 32 32" fill="currentColor">
      <path d="M16.6 2.8 30 13.6V30h-8.6v-8.4h-8.4V30H2V13.6L15.4 2.8a1 1 0 0 1 1.2 0Zm-1.2 2.2L4 14.9V28h6.4v-8.4h11.2V28H28V14.9L16.6 5.2l-1.2 0Z" />
    </svg>
    """
  end

  def icon(%{name: "carbon-store"} = assigns) do
    ~H"""
    <svg class={@class} aria-hidden="true" viewBox="0 0 32 32" fill="currentColor">
      <path d="M30 10.68l-2-6A1 1 0 0 0 27 4H5a1 1 0 0 0-1 .68l-2 6A1.19 1.19 0 0 0 2 11v6a1 1 0 0 0 1 1h1v10h2V18h6v10h16V18h1a1 1 0 0 0 1-1v-6a1.19 1.19 0 0 0-.32-.68ZM26 26H14v-8h12Zm2-10h-4v-4h-2v4h-5v-4h-2v4h-5v-4H8v4H4v-4.84L5.72 6h20.56L28 11.16Z" />
    </svg>
    """
  end

  def icon(%{name: "carbon-settings"} = assigns) do
    ~H"""
    <svg class={@class} aria-hidden="true" viewBox="0 0 32 32" fill="currentColor">
      <path d="M27 16.76c0-.25 0-.5 0-.76s0-.51 0-.77l1.92-1.68A2 2 0 0 0 29.3 11L26.94 7a2 2 0 0 0-1.73-1 2 2 0 0 0-.64.1l-2.43.82a11.35 11.35 0 0 0-1.31-.75l-.51-2.52a2 2 0 0 0-2-1.61h-4.72a2 2 0 0 0-2 1.61l-.51 2.52a11.48 11.48 0 0 0-1.32.75L7.43 6.06A2 2 0 0 0 6.79 6 2 2 0 0 0 5.06 7L2.7 11a2 2 0 0 0 .41 2.51L5 15.24c0 .25 0 .5 0 .76s0 .51 0 .77L3.11 18.45A2 2 0 0 0 2.7 21L5.06 25a2 2 0 0 0 1.73 1 2 2 0 0 0 .64-.1l2.43-.82a11.35 11.35 0 0 0 1.31.75l.51 2.52a2 2 0 0 0 2 1.61h4.72a2 2 0 0 0 2-1.61l.51-2.52a11.48 11.48 0 0 0 1.32-.75l2.42.82a2 2 0 0 0 .64.1 2 2 0 0 0 1.73-1L29.3 21a2 2 0 0 0-.41-2.51ZM25.21 24l-3.43-1.16a8.86 8.86 0 0 1-2.71 1.57L18.36 28h-4.72l-.71-3.55a9.36 9.36 0 0 1-2.7-1.57L6.79 24 4.43 20l2.72-2.4a8.9 8.9 0 0 1 0-3.13L4.43 12 6.79 8l3.43 1.16a8.86 8.86 0 0 1 2.71-1.57L13.64 4h4.72l.71 3.55a9.36 9.36 0 0 1 2.7 1.57L25.21 8 27.57 12l-2.72 2.4a8.9 8.9 0 0 1 0 3.13L27.57 20Z" />
      <path d="M16 22a6 6 0 1 1 6-6 5.94 5.94 0 0 1-6 6Zm0-10a3.91 3.91 0 0 0-4 4 3.91 3.91 0 0 0 4 4 3.91 3.91 0 0 0 4-4 3.91 3.91 0 0 0-4-4Z" />
    </svg>
    """
  end

  def icon(%{name: "carbon-chat"} = assigns) do
    ~H"""
    <svg class={@class} aria-hidden="true" viewBox="0 0 32 32" fill="currentColor">
      <path d="M17.74,30,16,29l4-7h6a2,2,0,0,0,2-2V8a2,2,0,0,0-2-2H6A2,2,0,0,0,4,8V20a2,2,0,0,0,2,2h9v2H6a4,4,0,0,1-4-4V8A4,4,0,0,1,6,4H26a4,4,0,0,1,4,4V20a4,4,0,0,1-4,4H21.16Z" />
      <path d="M8 10H24V12H8zM8 16H18V18H8z" />
    </svg>
    """
  end
end
