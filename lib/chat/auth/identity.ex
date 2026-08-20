defmodule Chat.Auth.Identity do
  @moduledoc false

  alias Chat.Accounts

  def sync_user(%{"sub" => subject} = claims, provider_response)
      when is_binary(subject) and subject != "" and is_map(provider_response) do
    with {:ok, matricula} <- stringify(claims["matricula"]),
         {:ok, codusur} <- stringify(claims["codusur"]),
         {:ok, filial} <- stringify(claims["filial"]) do
      attrs = %{
        email: claims["email"] || subject <> "@jurunense.com",
        username: provider_response["username"] || claims["username"] || subject,
        matricula: matricula,
        codusur: codusur,
        filial: filial,
        auth_provider: "external",
        auth_subject: subject
      }

      Accounts.find_or_create_external_user(attrs)
    else
      :error -> {:error, :invalid_claims}
    end
  end

  def sync_user(_claims, _provider_response), do: {:error, :invalid_claims}

  defp stringify(nil), do: {:ok, nil}
  defp stringify(value) when is_binary(value), do: {:ok, value}
  defp stringify(value) when is_integer(value), do: {:ok, Integer.to_string(value)}
  defp stringify(_value), do: :error
end
