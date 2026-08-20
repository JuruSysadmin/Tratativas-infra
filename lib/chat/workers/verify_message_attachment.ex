defmodule Chat.Workers.VerifyMessageAttachment do
  @moduledoc "Reconciles message attachment reservations with object storage."

  use Oban.Worker,
    queue: :attachments,
    max_attempts: 5,
    unique: [keys: [:attachment_id], period: 300]

  alias Chat.Messages.Attachments

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"attachment_id" => attachment_id}}) do
    case Attachments.verify_upload(attachment_id) do
      {:ok, _attachment} -> :ok
      {:error, :not_found} -> {:discard, :attachment_not_found}
      {:error, :invalid_upload} -> {:error, :invalid_upload}
      {:error, reason} -> {:error, reason}
    end
  end
end
