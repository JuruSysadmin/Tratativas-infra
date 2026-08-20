defmodule ChatWeb.MessageComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias ChatWeb.MessageComponents

  test "renders author and time above an incoming message" do
    html =
      render_component(&MessageComponents.message_item/1,
        dom_id: "message-1",
        msg: message("other-user", "mariana"),
        current_user: %{id: "current-user"},
        message_statuses: %{},
        online_user_ids: MapSet.new()
      )

    assert html =~ ~s(class="message-metadata")
    assert html =~ ~s(<span class="message-author">mariana</span>)
    assert html =~ ~s(<span class="message-time">07:24</span>)

    {author_position, _length} = :binary.match(html, "message-author")
    {content_position, _length} = :binary.match(html, "message-content")
    assert author_position < content_position
  end

  test "identifies the current user above their message" do
    html =
      render_component(&MessageComponents.message_item/1,
        dom_id: "message-1",
        msg: message("current-user", "joelson"),
        current_user: %{id: "current-user"},
        message_statuses: %{},
        online_user_ids: MapSet.new()
      )

    assert html =~ ~s(<span class="message-author">Você</span>)
    assert html =~ ~s(class="message-actions")
  end

  test "groups a consecutive message without repeating author metadata" do
    html =
      render_component(&MessageComponents.message_item/1,
        dom_id: "message-2",
        msg: message("other-user", "mariana"),
        current_user: %{id: "current-user"},
        message_statuses: %{},
        online_user_ids: MapSet.new(),
        compact: true
      )

    assert html =~ ~s(class="message message--bot message--grouped")

    css = File.read!(Path.expand("../../../assets/css/app.css", __DIR__))
    assert css =~ ".message--grouped .message-metadata"
    assert css =~ ".message--grouped .message-avatar"
  end

  test "places message deletion in a contextual overflow menu" do
    html =
      render_component(&MessageComponents.message_item/1,
        dom_id: "message-1",
        msg: message("current-user", "joelson"),
        current_user: %{id: "current-user"},
        message_statuses: %{},
        online_user_ids: MapSet.new()
      )

    assert html =~ ~s(<details class="message-action-menu">)
    assert html =~ ~s(class="message-action-menu-trigger")
    assert html =~ ~s(aria-label="Mais ações da mensagem")
    assert html =~ ~s(class="message-action-delete")
    assert html =~ ~s(phx-click="confirm_delete_message")

    css = File.read!(Path.expand("../../../assets/css/app.css", __DIR__))
    assert css =~ ".message-action-menu-trigger"
    assert css =~ "color: var(--cds-text-primary)"
    assert css =~ ".message--user:hover .message-content"
    assert css =~ "transition: opacity 110ms ease"
    assert css =~ "font: var(--cds-body-compact-01)"

    assert css =~
             ".message-action-delete .icon,\n.message-action-edit .icon,\n.message-action-menu-trigger .icon {\n  width: 14px;\n  height: 14px;"

    refute css =~ ".message-delete"
  end

  test "disables deletion after another user reads the message" do
    html =
      render_component(&MessageComponents.message_item/1,
        dom_id: "message-1",
        msg: Map.put(message("current-user", "joelson"), :reader_names, ["mariana"]),
        current_user: %{id: "current-user"},
        message_statuses: %{},
        online_user_ids: MapSet.new()
      )

    assert html =~ "Mensagem já lida; não pode ser excluída"
    assert html =~ "disabled"
  end

  test "places message editing in the contextual overflow menu for the author" do
    html =
      render_component(&MessageComponents.message_item/1,
        dom_id: "message-1",
        msg: message("current-user", "joelson"),
        current_user: %{id: "current-user"},
        message_statuses: %{},
        online_user_ids: MapSet.new()
      )

    assert html =~ ~s(class="message-action-edit")
    assert html =~ "Editar mensagem"
    assert html =~ ~s(phx-click="start_edit_message")
    assert html =~ ~s(phx-value-message_id="message-id")

    css = File.read!(Path.expand("../../../assets/css/app.css", __DIR__))
    assert css =~ ".message-action-delete,\n.message-action-edit"
    assert css =~ ".message-action-edit:hover"
  end

  test "does not offer editing for another user's message" do
    html =
      render_component(&MessageComponents.message_item/1,
        dom_id: "message-1",
        msg: message("other-user", "mariana"),
        current_user: %{id: "current-user"},
        message_statuses: %{},
        online_user_ids: MapSet.new()
      )

    refute html =~ "Editar mensagem"
    refute html =~ "message-action-edit"
  end

  test "marks an edited message with an accessible edited state" do
    html =
      render_component(&MessageComponents.message_item/1,
        dom_id: "message-1",
        msg:
          message("current-user", "joelson")
          |> Map.put(:edited_at, ~U[2026-07-19 11:30:00Z]),
        current_user: %{id: "current-user"},
        message_statuses: %{},
        online_user_ids: MapSet.new()
      )

    assert html =~ ~s(class="message-edited")
    assert html =~ ">editada<"
    assert html =~ ~s(title="Editada às 08:30")

    css = File.read!(Path.expand("../../../assets/css/app.css", __DIR__))
    assert css =~ ".message-edited"
  end

  test "omits the edited state when the message was never edited" do
    html =
      render_component(&MessageComponents.message_item/1,
        dom_id: "message-1",
        msg: message("current-user", "joelson"),
        current_user: %{id: "current-user"},
        message_statuses: %{},
        online_user_ids: MapSet.new()
      )

    refute html =~ "message-edited"
  end

  test "keeps every persisted message addressable for scroll while limiting read tracking" do
    html =
      render_component(&MessageComponents.message_item/1,
        dom_id: "message-1",
        msg: message("current-user", "joelson"),
        current_user: %{id: "current-user"},
        message_statuses: %{},
        online_user_ids: MapSet.new()
      )

    assert html =~ ~s(data-message-id="message-id")
    refute html =~ "data-mark-readable"
  end

  test "renders only persisted mention occurrences as escaped markup" do
    msg =
      message("other-user", "mariana")
      |> Map.put(:content, "Olá @joelson <script>alert(1)</script>")
      |> Map.put(:mentions, [
        %{
          mentioned_user_id: "mentioned-user",
          username_snapshot: "joelson",
          start_offset: 5,
          length: 8
        }
      ])

    html =
      render_component(&MessageComponents.message_item/1,
        dom_id: "message-1",
        msg: msg,
        current_user: %{id: "current-user"},
        message_statuses: %{},
        online_user_ids: MapSet.new()
      )

    assert html =~
             ~s(<span class="message-mention" data-mentioned-user-id="mentioned-user">@joelson</span>)

    assert html =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
    refute html =~ "<script>"
  end

  test "renders an online indicator over the avatar only when the author is online" do
    online_html =
      render_component(&MessageComponents.message_item/1,
        dom_id: "message-1",
        msg: message("other-user", "mariana"),
        current_user: %{id: "current-user"},
        message_statuses: %{},
        online_user_ids: MapSet.new(["other-user"])
      )

    offline_html =
      render_component(&MessageComponents.message_item/1,
        dom_id: "message-2",
        msg: message("offline-user", "renata"),
        current_user: %{id: "current-user"},
        message_statuses: %{},
        online_user_ids: MapSet.new(["other-user"])
      )

    assert online_html =~ ~s(class="message-avatar-wrapper")
    assert online_html =~ ~s(class="message-avatar-online-indicator" aria-hidden="true")
    refute offline_html =~ "message-avatar-online-indicator"
  end

  test "does not duplicate presence status on the current user's message" do
    html =
      render_component(&MessageComponents.message_item/1,
        dom_id: "message-1",
        msg: message("current-user", "joelson"),
        current_user: %{id: "current-user"},
        message_statuses: %{},
        online_user_ids: MapSet.new(["current-user"])
      )

    refute html =~ "message-avatar-online-indicator"
  end

  test "renders delivery status inside the message content after the text" do
    msg = Map.put(message("current-user", "joelson"), :reader_names, ["mariana"])

    html =
      render_component(&MessageComponents.message_item/1,
        dom_id: "message-1",
        msg: msg,
        current_user: %{id: "current-user"},
        message_statuses: %{"message-id" => :read},
        online_user_ids: MapSet.new()
      )

    {content_position, _length} = :binary.match(html, "message-content")
    {status_position, _length} = :binary.match(html, "message-delivery-status--read")

    assert content_position < status_position
    assert html =~ ~s(class="message-content message-content--with-status")
  end

  test "announces sending and failed delivery states to assistive technology" do
    for status <- [:sending, :failed] do
      html =
        render_component(&MessageComponents.message_item/1,
          dom_id: "message-#{status}",
          msg: Map.put(message("current-user", "joelson"), :status, status),
          current_user: %{id: "current-user"},
          message_statuses: %{},
          online_user_ids: MapSet.new()
        )

      assert html =~ ~s(role="status" aria-live="polite")
    end
  end

  test "gives delivery indicators an accessible status label" do
    msg = Map.put(message("current-user", "joelson"), :reader_names, ["mariana"])

    html =
      render_component(&MessageComponents.delivery_status/1,
        msg: msg,
        status: :read
      )

    assert html =~ ~s(aria-label="Lida. Lida por: mariana")
  end

  test "shows a readable delivery state next to the delivery indicator" do
    msg = message("current-user", "joelson")

    for {status, label} <- [
          {:sent, "Enviada"},
          {:delivered, "Entregue"},
          {:read, "Lida"}
        ] do
      html =
        render_component(&MessageComponents.delivery_status/1,
          msg: msg,
          status: status
        )

      assert html =~ label
      assert html =~ ~s(class="message-delivery-status)
    end
  end

  test "uses the compact message typography and Carbon chat surfaces" do
    css = File.read!(Path.expand("../../../assets/css/app.css", __DIR__))

    assert css =~ "--cds-body-short-01-font-size: 0.875rem"
    assert css =~ "--cds-body-short-01-line-height: 1.25rem"
    assert css =~ "--cds-highlight: #d0e2ff"
    assert css =~ "font: var(--cds-body-short-01)"
    assert css =~ "background: var(--cds-highlight)"
  end

  defp message(user_id, username) do
    %{
      id: "message-id",
      content: "Mensagem de teste",
      inserted_at: ~N[2026-07-19 10:24:00],
      status: :sent,
      delivered_count: 0,
      reader_names: [],
      user: %{id: user_id, username: username}
    }
  end
end
