defmodule Chat.Auth.Identity do
  @moduledoc false

  alias Chat.Accounts
  alias Chat.Auth.IdentityCache

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

      fingerprint = fingerprint(attrs)

      case IdentityCache.get("external", subject) do
        {:ok, user, ^fingerprint} ->
          {:ok, user}

        _miss_or_stale ->
          with {:ok, user} <- Accounts.find_or_create_external_user(attrs) do
            IdentityCache.put("external", subject, user, fingerprint)
            {:ok, user}
          end
      end
    else
      :error -> {:error, :invalid_claims}
    end
  end

  def sync_user(_claims, _provider_response), do: {:error, :invalid_claims}

  defp fingerprint(attrs) do
    [
      attrs.email,
      attrs.username,
      attrs.matricula,
      attrs.codusur,
      attrs.filial,
      attrs.auth_provider,
      attrs.auth_subject
    ]
    |> Enum.map_join("|", fn
      nil -> ""
      value -> to_string(value)
    end)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp stringify(nil), do: {:ok, nil}
  defp stringify(value) when is_binary(value), do: {:ok, value}
  defp stringify(value) when is_integer(value), do: {:ok, Integer.to_string(value)}
  defp stringify(_value), do: :error
end
