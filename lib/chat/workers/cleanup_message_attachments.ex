defmodule Chat.Workers.CleanupMessageAttachments do
  @moduledoc "Cleans message attachments without a message after the retention period."

  use Oban.Worker,
    queue: :attachments,
    max_attempts: 5,
    unique: [period: 3600]

  alias Chat.Messages.Attachments

  @retention_seconds 24 * 60 * 60

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    older_than = DateTime.add(DateTime.utc_now(), -@retention_seconds, :second)

    case Attachments.cleanup_orphaned(older_than: older_than) do
      {:ok, _count} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
