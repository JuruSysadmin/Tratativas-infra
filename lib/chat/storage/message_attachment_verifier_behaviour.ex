defmodule Chat.Storage.MessageAttachmentVerifier.Behaviour do
  @moduledoc false

  @callback head_object(String.t()) ::
              {:ok, %{size: non_neg_integer(), content_type: String.t()}} | {:error, term()}
end
