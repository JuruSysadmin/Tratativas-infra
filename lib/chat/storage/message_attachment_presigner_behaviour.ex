defmodule Chat.Storage.MessageAttachmentPresigner.Behaviour do
  @moduledoc false

  @callback presign_upload(%{storage_key: String.t(), content_type: String.t()}) ::
              {:ok, String.t()} | {:error, term()}

  @callback presign_download(%{storage_key: String.t(), filename: String.t()}) ::
              {:ok, String.t()} | {:error, term()}
end
