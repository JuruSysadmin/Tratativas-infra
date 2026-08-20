defmodule Chat.Storage.MessageAttachmentDeleterBehaviour do
  @moduledoc false

  @callback delete_object(String.t()) :: :ok | {:error, term()}
end
