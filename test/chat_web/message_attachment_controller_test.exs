defmodule ChatWeb.MessageAttachmentControllerTest do
  use ChatWeb.ConnCase, async: false

  alias Chat.Auth.Identity
  alias Chat.Rooms

  setup do
    {:ok, user} = Identity.sync_user(%{"sub" => "message-attachment-controller-user"}, %{})

    previous_module = Application.get_env(:chat, :authenticator_module)
    previous_pid = Application.get_env(:chat, :authenticator_spy_pid)
    previous_user = Application.get_env(:chat, :authenticator_spy_user)
    previous_presigner = Application.get_env(:chat, :message_attachment_presigner)

    Application.put_env(:chat, :authenticator_module, Chat.AuthenticatorSpy)
    Application.put_env(:chat, :authenticator_spy_pid, self())
    Application.put_env(:chat, :authenticator_spy_user, user)

    Application.put_env(
      :chat,
      :message_attachment_presigner,
      Chat.TestSupport.MessageAttachmentPresigner
    )

    on_exit(fn ->
      restore_env(:authenticator_module, previous_module)
      restore_env(:authenticator_spy_pid, previous_pid)
      restore_env(:authenticator_spy_user, previous_user)
      restore_env(:message_attachment_presigner, previous_presigner)
    end)

    %{user: user}
  end

  test "returns a presigned upload for an authorized message", %{conn: conn, user: user} do
    {:ok, room} = Rooms.create_room(%{"name" => "Attachment API"}, user.id)

    conn =
      conn
      |> put_req_header("authorization", "Bearer valid-token")
      |> post(~p"/api/rooms/#{room.id}/attachments/presign", %{
        attachment: %{filename: "documento.pdf", content_type: "application/pdf", size: 128}
      })

    assert %{
             "attachment" => %{
               "content_type" => "application/pdf",
               "filename" => "documento.pdf",
               "status" => "pending",
               "upload_url" => "https://storage.test/upload/" <> _,
               "expires_at" => expires_at
             }
           } = json_response(conn, 201)

    assert is_binary(expires_at)
  end

  test "rejects an oversized attachment", %{conn: conn, user: user} do
    {:ok, room} = Rooms.create_room(%{"name" => "Attachment Limit"}, user.id)

    conn =
      conn
      |> put_req_header("authorization", "Bearer valid-token")
      |> post(~p"/api/rooms/#{room.id}/attachments/presign", %{
        attachment: %{filename: "large.pdf", content_type: "application/pdf", size: 10_485_761}
      })

    assert json_response(conn, 422) == %{"error" => "file_too_large"}
  end

  test "does not authorize a message from another room", %{conn: conn, user: user} do
    {:ok, other_user} = Identity.sync_user(%{"sub" => "message-attachment-other-user"}, %{})
    {:ok, other_room} = Rooms.create_room(%{"name" => "Other Attachment Room"}, other_user.id)

    conn =
      conn
      |> put_req_header("authorization", "Bearer valid-token")
      |> post(~p"/api/rooms/#{other_room.id}/attachments/presign", %{
        attachment: %{filename: "privado.pdf", content_type: "application/pdf", size: 128}
      })

    assert json_response(conn, 404) == %{"error" => "attachment_not_found"}
    refute user.id == other_user.id
  end

  defp restore_env(key, nil), do: Application.delete_env(:chat, key)
  defp restore_env(key, value), do: Application.put_env(:chat, key, value)
end
