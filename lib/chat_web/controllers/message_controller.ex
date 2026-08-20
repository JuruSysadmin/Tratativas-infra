defmodule ChatWeb.MessageController do
  @moduledoc "HTTP endpoints for listing, creating, and deleting messages."

  use ChatWeb, :controller

  alias Chat.Messages
  alias Chat.Messages.Attachments
  alias Chat.Repo
  alias Chat.Rooms

  def index(conn, %{"room_id" => room_id} = params) do
    user = conn.assigns.current_user

    if Rooms.room_member?(user.id, room_id) do
      list_messages(conn, room_id, params)
    else
      forbidden(conn)
    end
  end

  defp list_messages(conn, room_id, params) do
    with {:ok, limit} <- parse_limit(params["limit"]),
         {:ok, before_id} <- parse_before(params["before"]) do
      opts = [limit: limit, before: before_id]
      messages = Messages.list_messages(room_id, opts)
      has_more = length(messages) == opts[:limit]

      messages_data =
        Enum.map(messages, fn msg ->
          %{
            id: msg.id,
            content: msg.content,
            user: %{
              id: msg.user.id,
              username: msg.user.username
            },
            room_id: msg.room_id,
            inserted_at: msg.inserted_at,
            edited_at: msg.edited_at,
            attachments: Attachments.message_payload_attachments(msg)
          }
        end)

      json(conn, %{messages: messages_data, has_more: has_more})
    else
      {:error, :invalid_limit} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid_limit"})

      {:error, :invalid_before} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid_before"})
    end
  end

  defp parse_limit(nil), do: {:ok, 50}

  defp parse_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {limit, ""} when limit in 1..100 -> {:ok, limit}
      _other -> {:error, :invalid_limit}
    end
  end

  defp parse_limit(_value), do: {:error, :invalid_limit}

  defp parse_before(nil), do: {:ok, nil}

  defp parse_before(value) do
    case Ecto.UUID.cast(value) do
      {:ok, before_id} -> {:ok, before_id}
      :error -> {:error, :invalid_before}
    end
  end

  def create(conn, %{"room_id" => room_id, "message" => message_params})
      when is_map(message_params) do
    user = conn.assigns.current_user

    if Rooms.room_member?(user.id, room_id) do
      create_message(conn, user, room_id, message_params)
    else
      forbidden(conn)
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "invalid_message"})
  end

  defp create_message(conn, user, room_id, message_params) do
    {client_id, attrs} = Map.pop(message_params, "client_id")
    attrs = Map.put(attrs, "room_id", room_id)

    case Messages.create_message(attrs, user.id, room_id, client_id_opts(client_id)) do
      {:ok, message} ->
        message = Repo.preload(message, :user)

        conn
        |> put_status(:created)
        |> json(%{
          message: %{
            id: message.id,
            content: message.content,
            user: %{
              id: message.user.id,
              username: message.user.username
            },
            room_id: message.room_id,
            inserted_at: message.inserted_at,
            edited_at: message.edited_at,
            attachments: Attachments.message_payload_attachments(message)
          }
        })

      {:error, :client_id_conflict} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "client_id_conflict"})

      {:error, :invalid_client_id} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid_client_id"})

      {:error, :forbidden} ->
        forbidden(conn)

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  defp client_id_opts(nil), do: []
  defp client_id_opts(client_id), do: [client_id: client_id]

  def delete(conn, %{"room_id" => room_id, "id" => id}) do
    user = conn.assigns.current_user

    case Messages.delete_own_unread_message(id, user.id, room_id) do
      {:ok, _message} ->
        send_resp(conn, :no_content, "")

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "message_not_found"})

      {:error, :not_member} ->
        forbidden(conn)

      {:error, :not_authorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "not_authorized"})

      {:error, :already_read} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "message_already_read"})

      {:error, _changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "message_delete_failed"})
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp forbidden(conn) do
    conn
    |> put_status(:forbidden)
    |> json(%{error: "not_a_member"})
  end
end
