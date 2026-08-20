defmodule ChatWeb.MessageAttachmentController do
  use ChatWeb, :controller

  alias Chat.Messages.Attachments

  def presign(conn, %{"room_id" => room_id, "attachment" => attrs})
      when is_map(attrs) do
    user_id = conn.assigns.current_user.id

    Attachments.presign_upload(user_id, room_id, attrs)
    |> render_presign_result(conn)
  end

  def presign(conn, _params), do: error(conn, :bad_request, "invalid_attachment")

  def confirm(conn, %{"room_id" => room_id, "attachment_id" => attachment_id}) do
    Attachments.confirm_upload(conn.assigns.current_user.id, room_id, attachment_id)
    |> render_confirm_result(conn)
  end

  def confirm(conn, _params), do: error(conn, :bad_request, "invalid_attachment")

  defp render_presign_result({:ok, attachment, upload_url}, conn) do
    conn
    |> put_status(:created)
    |> json(%{
      attachment: %{
        id: attachment.id,
        filename: attachment.filename,
        content_type: attachment.content_type,
        size: attachment.size,
        status: attachment.status,
        upload_url: upload_url,
        expires_at: DateTime.to_iso8601(attachment.expires_at),
        expires_in: presign_ttl_seconds()
      }
    })
  end

  defp render_presign_result({:error, reason}, conn)
       when reason in [:invalid_id, :invalid_attachment],
       do: error(conn, :bad_request, Atom.to_string(reason))

  defp render_presign_result({:error, reason}, conn)
       when reason in [
              :invalid_filename,
              :invalid_content_type,
              :unsupported_content_type,
              :invalid_size,
              :file_too_large,
              :attachment_limit_reached
            ],
       do: error(conn, :unprocessable_entity, Atom.to_string(reason))

  defp render_presign_result({:error, :not_found}, conn),
    do: error(conn, :not_found, "attachment_not_found")

  defp render_presign_result({:error, :storage_unavailable}, conn),
    do: error(conn, :service_unavailable, "storage_unavailable")

  defp render_presign_result({:error, %Ecto.Changeset{} = changeset}, conn) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: format_errors(changeset)})
  end

  defp render_confirm_result({:ok, attachment}, conn) do
    json(conn, %{attachment: %{id: attachment.id, status: attachment.status}})
  end

  defp render_confirm_result({:error, reason}, conn)
       when reason == :expired,
       do: error(conn, :gone, "attachment_expired")

  defp render_confirm_result({:error, reason}, conn)
       when reason in [:invalid_id, :invalid_upload],
       do: error(conn, :unprocessable_entity, Atom.to_string(reason))

  defp render_confirm_result({:error, :not_found}, conn),
    do: error(conn, :not_found, "attachment_not_found")

  defp presign_ttl_seconds do
    :chat
    |> Application.get_env(:message_attachment_storage, [])
    |> Keyword.get(:presign_ttl_seconds, 300)
  end

  defp error(conn, status, reason) do
    conn
    |> put_status(status)
    |> json(%{error: reason})
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
