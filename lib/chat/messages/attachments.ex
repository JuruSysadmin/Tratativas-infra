defmodule Chat.Messages.Attachments do
  @moduledoc "Authorized message attachment reservations and presigned uploads."

  import Ecto.Query
  require Logger

  alias Chat.Messages.MessageAttachment
  alias Chat.Repo
  alias Chat.Rooms.RoomMember
  alias Chat.Storage.MessageAttachmentDeleter
  alias Chat.Workers.VerifyMessageAttachment

  @max_file_size 10 * 1024 * 1024
  @max_attachments_per_message 5
  @allowed_content_types ~w(application/pdf image/jpeg image/png)
  @verification_delay_seconds 30
  @attachment_ttl_seconds 5 * 60

  def payload(%MessageAttachment{} = attachment, opts \\ []) do
    download_url =
      case presigner(opts).presign_download(attachment) do
        {:ok, url} ->
          url

        {:error, reason} ->
          Logger.error(
            "message attachment download URL generation failed " <>
              "attachment_id=#{attachment.id} error=#{inspect(reason)}"
          )

          nil
      end

    %{
      id: attachment.id,
      filename: attachment.filename,
      content_type: attachment.content_type,
      size: attachment.size,
      download_url: download_url
    }
  end

  def message_payload_attachments(%{attachments: attachments}, opts \\ []) do
    Enum.map(attachments, &payload(&1, opts))
  end

  def presign_upload(user_id, room_id, attrs, opts \\ []) do
    with {:ok, user_id} <- Ecto.UUID.cast(user_id),
         {:ok, room_id} <- Ecto.UUID.cast(room_id),
         {:ok, attrs} <- validate_upload_attrs(attrs),
         {:ok, attachment} <- reserve_attachment(user_id, room_id, attrs),
         {:ok, upload_url} <- presign(attachment, opts),
         {:ok, _job} <- enqueue_verification(attachment.id) do
      {:ok, attachment, upload_url}
    else
      :error -> {:error, :invalid_id}
      {:error, :storage_unavailable} = error -> error
      {:error, reason} -> {:error, reason}
    end
  end

  def verify_upload(attachment_id, opts \\ []) do
    with {:ok, attachment_id} <- Ecto.UUID.cast(attachment_id),
         %MessageAttachment{} = attachment <- Repo.get(MessageAttachment, attachment_id),
         {:ok, attachment} <- verify_attachment(attachment, opts) do
      {:ok, attachment}
    else
      :error -> {:error, :invalid_id}
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def confirm_upload(user_id, room_id, attachment_id, opts \\ []) do
    with {:ok, user_id} <- Ecto.UUID.cast(user_id),
         {:ok, room_id} <- Ecto.UUID.cast(room_id),
         {:ok, attachment_id} <- Ecto.UUID.cast(attachment_id),
         %MessageAttachment{} = attachment <-
           get_owned_attachment(user_id, room_id, attachment_id),
         {:ok, attachment} <- confirm_attachment(attachment, opts) do
      {:ok, attachment}
    else
      :error -> {:error, :invalid_id}
      nil -> {:error, :not_found}
      {:error, :not_found} -> {:error, :not_found}
      {:error, :expired} -> {:error, :expired}
      {:error, _reason} -> {:error, :invalid_upload}
    end
  end

  def cleanup_orphaned(opts \\ []) do
    older_than = Keyword.fetch!(opts, :older_than)
    deleter = deleter(opts)

    Repo.all(
      from attachment in MessageAttachment,
        where:
          is_nil(attachment.message_id) and is_nil(attachment.deleted_at) and
            attachment.inserted_at < ^older_than,
        order_by: [asc: attachment.inserted_at],
        limit: 100
    )
    |> Enum.reduce_while({:ok, 0}, fn attachment, {:ok, count} ->
      case cleanup_attachment(attachment, deleter) do
        :ok -> {:cont, {:ok, count + 1}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp confirm_attachment(%MessageAttachment{status: :available} = attachment, _opts),
    do: {:ok, attachment}

  defp confirm_attachment(attachment, opts) do
    if expired?(attachment), do: {:error, :expired}, else: verify_attachment(attachment, opts)
  end

  defp verify_attachment(%MessageAttachment{status: :available} = attachment, _opts),
    do: {:ok, attachment}

  defp verify_attachment(attachment, opts) do
    with {:ok, object} <- verifier(opts).head_object(attachment.storage_key),
         :ok <- validate_object(attachment, object) do
      Repo.update(Ecto.Changeset.change(attachment, status: :available))
    end
  end

  def attach_to_message(repo, user_id, room_id, message_id, attachment_ids)
      when is_list(attachment_ids) do
    with {:ok, ids} <- cast_ids(attachment_ids),
         true <- length(ids) <= @max_attachments_per_message,
         attachments <- owned_available_attachments(repo, user_id, room_id, ids),
         true <- length(attachments) == length(ids) do
      repo.update_all(
        from(attachment in MessageAttachment,
          where: attachment.id in ^ids and is_nil(attachment.message_id)
        ),
        set: [message_id: message_id]
      )

      {:ok, attachments}
    else
      false -> {:error, :invalid_attachments}
      {:error, :invalid_id} -> {:error, :invalid_attachments}
    end
  end

  def attach_to_message(_repo, _user_id, _room_id, _message_id, _attachment_ids),
    do: {:error, :invalid_attachments}

  defp validate_upload_attrs(attrs) when is_map(attrs) do
    filename = Map.get(attrs, "filename")
    content_type = Map.get(attrs, "content_type")
    size = Map.get(attrs, "size")

    cond do
      not is_binary(filename) or filename == "" ->
        {:error, :invalid_filename}

      not is_binary(content_type) ->
        {:error, :invalid_content_type}

      content_type not in @allowed_content_types ->
        {:error, :unsupported_content_type}

      not is_integer(size) or size < 0 ->
        {:error, :invalid_size}

      size > @max_file_size ->
        {:error, :file_too_large}

      true ->
        {:ok,
         %{
           filename: Path.basename(filename),
           content_type: content_type,
           size: size,
           metadata: Map.get(attrs, "metadata", %{})
         }}
    end
  end

  defp validate_upload_attrs(_attrs), do: {:error, :invalid_attachment}

  defp reserve_attachment(user_id, room_id, attrs) do
    Repo.transaction(fn ->
      with :ok <- authorize_room(user_id, room_id),
           {:ok, attachment} <- insert_reservation(user_id, room_id, attrs) do
        {:ok, attachment}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, {:ok, attachment}} -> {:ok, attachment}
      {:ok, {:error, changeset}} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_reservation(user_id, room_id, attrs) do
    attachment_id = Ecto.UUID.generate()

    %MessageAttachment{
      id: attachment_id,
      room_id: room_id,
      uploaded_by_id: user_id
    }
    |> MessageAttachment.reservation_changeset(%{
      storage_key: storage_key(room_id, attachment_id, attrs.filename),
      filename: attrs.filename,
      content_type: attrs.content_type,
      size: attrs.size,
      metadata: attrs.metadata,
      expires_at: DateTime.add(DateTime.utc_now(), @attachment_ttl_seconds, :second)
    })
    |> Repo.insert()
  end

  defp authorize_room(user_id, room_id) do
    query =
      from member in RoomMember, where: member.user_id == ^user_id and member.room_id == ^room_id

    if Repo.exists?(query), do: :ok, else: {:error, :not_found}
  end

  defp get_owned_attachment(user_id, room_id, attachment_id) do
    Repo.one(
      from attachment in MessageAttachment,
        where:
          attachment.id == ^attachment_id and attachment.room_id == ^room_id and
            attachment.uploaded_by_id == ^user_id and is_nil(attachment.message_id) and
            is_nil(attachment.deleted_at) and
            attachment.status in [:pending, :uploading, :available]
    )
  end

  defp verifier(opts) do
    Keyword.get(
      opts,
      :verifier,
      Application.get_env(
        :chat,
        :message_attachment_verifier,
        Chat.Storage.MessageAttachmentVerifier
      )
    )
  end

  defp validate_object(attachment, %{size: size, content_type: content_type}) do
    if size == attachment.size and content_type == attachment.content_type,
      do: :ok,
      else: {:error, :invalid_upload}
  end

  defp enqueue_verification(attachment_id) do
    %{attachment_id: attachment_id}
    |> VerifyMessageAttachment.new(schedule_in: @verification_delay_seconds)
    |> Oban.insert()
  end

  defp cast_ids(ids) do
    results = Enum.map(ids, &Ecto.UUID.cast/1)

    if Enum.all?(results, &match?({:ok, _}, &1)),
      do: {:ok, Enum.map(results, &elem(&1, 1))},
      else: {:error, :invalid_id}
  end

  defp owned_available_attachments(repo, user_id, room_id, ids) do
    repo.all(
      from attachment in MessageAttachment,
        where:
          attachment.id in ^ids and attachment.room_id == ^room_id and
            attachment.uploaded_by_id == ^user_id and attachment.status == :available and
            is_nil(attachment.message_id) and is_nil(attachment.deleted_at),
        lock: "FOR UPDATE"
    )
  end

  defp presign(attachment, opts) do
    presigner = presigner(opts)

    case presigner.presign_upload(attachment) do
      {:ok, upload_url} -> {:ok, upload_url}
      {:error, _reason} -> mark_failed(attachment, :storage_unavailable)
    end
  end

  defp presigner(opts) do
    Keyword.get(
      opts,
      :presigner,
      Application.get_env(
        :chat,
        :message_attachment_presigner,
        Chat.Storage.MessageAttachmentPresigner
      )
    )
  end

  defp deleter(opts) do
    Keyword.get(opts, :deleter, MessageAttachmentDeleter)
  end

  defp cleanup_attachment(attachment, deleter) do
    Repo.transaction(fn ->
      locked_attachment =
        Repo.one!(
          from item in MessageAttachment,
            where:
              item.id == ^attachment.id and is_nil(item.message_id) and
                is_nil(item.deleted_at),
            lock: "FOR UPDATE"
        )

      with :ok <- deleter.delete_object(locked_attachment.storage_key),
           {:ok, _attachment} <-
             Repo.update(Ecto.Changeset.change(locked_attachment, deleted_at: DateTime.utc_now())) do
        :ok
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    Ecto.NoResultsError -> :ok
  end

  defp mark_failed(attachment, reason) do
    changeset = Ecto.Changeset.change(attachment, status: :failed)
    _ = Repo.update(changeset)
    {:error, reason}
  end

  defp expired?(%MessageAttachment{expires_at: expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now()) == :lt
  end

  defp storage_key(message_id, attachment_id, filename) do
    extension =
      filename
      |> Path.extname()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9.]/, "")

    "message-attachments/#{message_id}/#{attachment_id}#{extension}"
  end
end
