defmodule ChatWeb.ChatAreaComponentTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias ChatWeb.ChatAreaComponent

  test "groups consecutive messages from the same author" do
    current_user = %{id: "current-user", username: "joelson"}

    html =
      render_component(&ChatAreaComponent.chat_area/1, %{
        current_room: %{id: "room-1", name: "Equipe", members: [], creator_id: "current-user"},
        current_user: current_user,
        messages: [
          {"message-1", message("other-user", "mariana", "Primeira")},
          {"message-2", message("other-user", "mariana", "Segunda")}
        ],
        has_more_messages: false,
        pending_messages: %{},
        pending_message_order: [],
        status_messages: [],
        typing_users: [],
        input_text: "",
        mention_suggestions: [],
        message_statuses: %{},
        rooms: [],
        online_users: []
      })

    assert html =~ ~s(id="message-1")
    assert html =~ ~s(id="message-2")
    assert html =~ ~s(class="message message--bot message--grouped")
  end

  test "normalizes incomplete status and typing users without crashing" do
    current_user = %{id: "current-user", username: "joelson"}

    html =
      render_component(&ChatAreaComponent.chat_area/1, %{
        current_room: %{id: "room-1", name: "Equipe", members: [], creator_id: "current-user"},
        current_user: current_user,
        messages: [],
        has_more_messages: false,
        pending_messages: %{},
        pending_message_order: [],
        status_messages: [%{kind: :joined}, %{username: "mariana"}, :invalid],
        typing_users: [%{id: "other-user"}, %{username: "mariana"}, :invalid],
        input_text: "",
        mention_suggestions: [],
        message_statuses: %{},
        rooms: [],
        online_users: [%{username: "mariana"}, :invalid]
      })

    assert html =~ "Usuário entrou na sala"
    assert html =~ "Usuário saiu da sala"
    assert html =~ "mariana"
    assert html =~ "está digitando..."
  end

  test "renders the room title as the conversation heading" do
    html =
      render_component(&ChatAreaComponent.chat_area/1, %{
        current_room: %{id: "room-1", name: "Equipe", members: [], creator_id: "current-user"},
        current_user: %{id: "current-user", username: "joelson"},
        messages: [],
        has_more_messages: false,
        pending_messages: %{},
        pending_message_order: [],
        status_messages: [],
        typing_users: [],
        input_text: "",
        mention_suggestions: [],
        message_statuses: %{},
        rooms: [],
        online_users: []
      })

    assert html =~ ~s(<h1 id="chat-room-title">Equipe</h1>)
    assert html =~ ~s(class="room-member-summary")
  end

  defp message(user_id, username, content) do
    %{
      id: user_id <> "-" <> content <> "-message",
      content: content,
      inserted_at: ~N[2026-07-19 10:24:00],
      status: :sent,
      delivered_count: 0,
      reader_names: [],
      user: %{id: user_id, username: username}
    }
  end
end
