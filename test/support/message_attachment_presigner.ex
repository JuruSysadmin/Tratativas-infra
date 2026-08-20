defmodule Chat.TestSupport.MessageAttachmentPresigner do
  @moduledoc false

  @behaviour Chat.Storage.MessageAttachmentPresigner.Behaviour

  @impl true
  def presign_upload(%{storage_key: storage_key}) do
    {:ok, "https://storage.test/upload/" <> storage_key}
  end

  @impl true
  def presign_download(%{storage_key: storage_key}) do
    {:ok, "https://storage.test/download/" <> storage_key}
  end
end
