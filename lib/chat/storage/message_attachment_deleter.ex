defmodule Chat.Storage.MessageAttachmentDeleter do
  @moduledoc "Deletes message attachment objects from external storage."

  @behaviour Chat.Storage.MessageAttachmentDeleterBehaviour

  @impl true
  def delete_object(storage_key) do
    config = Application.fetch_env!(:chat, :message_attachment_storage)
    bucket = Keyword.fetch!(config, :bucket)

    bucket
    |> ExAws.S3.delete_object(storage_key)
    |> ExAws.request(storage_options(config))
    |> case do
      {:ok, _response} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp storage_options(config) do
    Enum.reduce([:region, :host, :scheme, :port], [], fn key, options ->
      case Keyword.get(config, key) do
        nil -> options
        value -> Keyword.put(options, key, value)
      end
    end)
  end
end
