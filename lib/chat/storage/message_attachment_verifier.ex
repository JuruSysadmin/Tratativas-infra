defmodule Chat.Storage.MessageAttachmentVerifier do
  @moduledoc "Checks uploaded message attachments in object storage."

  @behaviour Chat.Storage.MessageAttachmentVerifier.Behaviour

  @impl true
  def head_object(storage_key) do
    config = Application.fetch_env!(:chat, :message_attachment_storage)
    bucket = Keyword.fetch!(config, :bucket)

    ExAws.S3.head_object(bucket, storage_key)
    |> ExAws.request(storage_options(config))
    |> case do
      {:ok, %{headers: headers}} ->
        {:ok,
         %{
           size: header_integer(headers, "content-length"),
           content_type: header_value(headers, "content-type")
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp header_value(headers, name) do
    Enum.find_value(headers, fn {key, value} ->
      if String.downcase(to_string(key)) == name, do: to_string(value)
    end)
  end

  defp header_integer(headers, name), do: headers |> header_value(name) |> String.to_integer()

  defp storage_options(config) do
    Enum.reduce([:region, :host, :scheme, :port], [], fn key, options ->
      case Keyword.get(config, key) do
        nil -> options
        value -> Keyword.put(options, key, value)
      end
    end)
  end
end
