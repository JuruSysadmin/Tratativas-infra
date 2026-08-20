defmodule ChatWeb.MentionAutocompleteTest do
  use ChatWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Chat.Auth.Identity
  alias Chat.Rooms

  test "suggests room members and inserts the selected mention", %{conn: conn} do
    {:ok, author} = Identity.sync_user(%{"sub" => "autocomplete-author"}, %{})
    {:ok, member} = Identity.sync_user(%{"sub" => "autocomplete-mariana"}, %{})
    {:ok, outsider} = Identity.sync_user(%{"sub" => "autocomplete-outsider"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Autocomplete"}, author.id)
    assert {:ok, _membership} = Rooms.join_room(member.id, room.id)

    conn = init_test_session(conn, %{"user_id" => author.id})
    {:ok, view, _html} = live(conn, ~p"/chat")

    view
    |> element(~s(#room-select-#{room.id}))
    |> render_click()

    view
    |> form("#message-form", %{"text" => "Olá @autocomplete-m"})
    |> render_change()

    assert has_element?(view, ~s(textarea[name="text"][role="combobox"]))
    assert has_element?(view, ~s(textarea[name="text"][aria-expanded="true"]))
    assert has_element?(view, ~s(textarea[name="text"][aria-controls="mention-suggestions"]))
    assert has_element?(view, ~s(textarea[name="text"][phx-debounce="0"]))
    assert has_element?(view, ~s(#message-form[phx-hook="MessageOutbox"]))
    assert has_element?(view, ~s(#mention-option-#{member.id}[aria-selected="false"]))

    html = render(view)
    {input_offset, _length} = :binary.match(html, ~s(name="text"))
    {listbox_offset, _length} = :binary.match(html, ~s(id="mention-suggestions"))
    assert input_offset < listbox_offset

    assert has_element?(
             view,
             ~s(#mention-suggestions button[phx-value-username="#{member.username}"])
           )

    refute has_element?(
             view,
             ~s(#mention-suggestions button[phx-value-username="#{author.username}"])
           )

    refute has_element?(
             view,
             ~s(#mention-suggestions button[phx-value-username="#{outsider.username}"])
           )

    render_hook(view, "dismiss_mentions", %{})
    refute has_element?(view, "#mention-suggestions")

    view
    |> form("#message-form", %{"text" => "Olá @autocomplete-m"})
    |> render_change()

    view
    |> element(~s(button[phx-click="select_mention"][phx-value-username="#{member.username}"]))
    |> render_click()

    assert has_element?(
             view,
             ~s(#message-form textarea[name="text"])
           )

    assert render(view) =~ "Olá @#{member.username} "

    refute has_element?(view, "#mention-suggestions")
  end

  test "mention combobox preserves the first pointer selection before blur" do
    hook =
      File.read!(Path.expand("../../../assets/js/hooks/mention_combobox.js", __DIR__))

    assert hook =~ "event.preventDefault()"
    assert hook =~ "event.stopPropagation()"
    assert hook =~ "this.el.addEventListener(\"pointerdown\", this.onPointerDown)"
  end

  test "suggests a member with spaces and inserts a quoted mention", %{conn: conn} do
    {:ok, author} = Identity.sync_user(%{"sub" => "autocomplete-full-name-author"}, %{})

    {:ok, member} =
      Identity.sync_user(
        %{"sub" => "autocomplete-full-name-member"},
        %{"username" => "VANESSA SOUSA DE PAIVA"}
      )

    {:ok, room} = Rooms.create_room(%{"name" => "Autocomplete nome completo"}, author.id)
    assert {:ok, _membership} = Rooms.join_room(member.id, room.id)

    conn = init_test_session(conn, %{"user_id" => author.id})
    {:ok, view, _html} = live(conn, ~p"/chat")

    view
    |> element(~s(#room-select-#{room.id}))
    |> render_click()

    view
    |> form("#message-form", %{"text" => "Olá @VAN"})
    |> render_change()

    assert has_element?(
             view,
             ~s(#mention-suggestions button[phx-value-username="VANESSA SOUSA DE PAIVA"])
           )

    view
    |> element(~s(button[phx-click="select_mention"][phx-value-username="#{member.username}"]))
    |> render_click()

    assert render(view) =~ ~s(Olá @&quot;VANESSA SOUSA DE PAIVA&quot; )
  end

  test "a forged selection outside current suggestions is ignored", %{conn: conn} do
    {:ok, author} = Identity.sync_user(%{"sub" => "autocomplete-forged-author"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Autocomplete seguro"}, author.id)

    conn = init_test_session(conn, %{"user_id" => author.id})
    {:ok, view, _html} = live(conn, ~p"/chat")

    view
    |> element(~s(#room-select-#{room.id}))
    |> render_click()

    render_click(view, "select_mention", %{"username" => "outsider"})

    assert has_element?(view, "#message-form")
    refute render(view) =~ "@outsider"
  end

  test "forged non-binary composer payloads do not terminate the LiveView", %{conn: conn} do
    {:ok, user} = Identity.sync_user(%{"sub" => "autocomplete-invalid-payload"}, %{})
    {:ok, room} = Rooms.create_room(%{"name" => "Payload seguro"}, user.id)

    conn = init_test_session(conn, %{"user_id" => user.id})
    {:ok, view, _html} = live(conn, ~p"/chat")

    view
    |> element(~s(#room-select-#{room.id}))
    |> render_click()

    render_change(view, "update_input", %{"text" => %{}})
    render_submit(view, "send_message", %{"text" => []})
    render_hook(view, "mark_read", %{"message_ids" => 1})

    assert has_element?(view, "#message-form")
  end
end
