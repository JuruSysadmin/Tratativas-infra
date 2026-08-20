defmodule Chat.Storage.MessageAttachmentPresigner do
  @moduledoc "Generates short-lived presigned URLs for message attachments."

  @behaviour Chat.Storage.MessageAttachmentPresigner.Behaviour

  @impl true
  def presign_upload(%{storage_key: storage_key, content_type: content_type}) do
    config = Application.fetch_env!(:chat, :message_attachment_storage)
    bucket = Keyword.fetch!(config, :bucket)
    expires_in = Keyword.get(config, :presign_ttl_seconds, 300)

    storage_config =
      :s3
      |> ExAws.Config.new(storage_options(config))

    ExAws.S3.presigned_url(
      storage_config,
      :put,
      bucket,
      storage_key,
      expires_in: expires_in,
      headers: [{"content-type", content_type}]
    )
  end

  @impl true
  def presign_download(%{storage_key: storage_key}) do
    config = Application.fetch_env!(:chat, :message_attachment_storage)
    bucket = Keyword.fetch!(config, :bucket)
    expires_in = Keyword.get(config, :presign_ttl_seconds, 300)

    ExAws.S3.presigned_url(
      :s3 |> ExAws.Config.new(storage_options(config)),
      :get,
      bucket,
      storage_key,
      expires_in: expires_in
    )
  end

  defp storage_options(config) do
    [:region]
    |> Enum.reduce([], fn key, options ->
      put_if_present(options, key, Keyword.get(config, key))
    end)
    |> then(fn options -> put_if_present(options, :host, Keyword.get(config, :host)) end)
    |> then(fn options -> put_if_present(options, :scheme, Keyword.get(config, :scheme)) end)
    |> then(fn options -> put_if_present(options, :port, Keyword.get(config, :port)) end)
  end

  defp put_if_present(options, _key, nil), do: options
  defp put_if_present(options, key, value), do: Keyword.put(options, key, value)
end
