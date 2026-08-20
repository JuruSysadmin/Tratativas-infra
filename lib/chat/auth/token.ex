defmodule Chat.Auth.Token do
  @moduledoc "External RS256 JWT validation through the configured JWKS endpoint."

  use Joken.Config

  add_hook(JokenJwks, strategy: Chat.Auth.JwksStrategy)

  def validate_jwks_token(token) do
    auth_config = Application.fetch_env!(:chat, :auth)

    case auth_config[:jwks_uri] do
      nil ->
        {:error, :missing_config}

      _jwks_uri ->
        with {:ok, claims} <- verify(token) do
          validate_claims(claims)
        end
    end
  end

  def validate_claims(%{"sub" => subject, "exp" => exp} = claims)
      when is_binary(subject) and subject != "" and is_integer(exp) do
    auth_config = Application.fetch_env!(:chat, :auth)
    now = System.system_time(:second)

    cond do
      exp < now ->
        {:error, :token_expired}

      !is_binary(auth_config[:issuer]) || claims["iss"] != auth_config[:issuer] ->
        {:error, :invalid_issuer}

      !is_binary(auth_config[:audience]) ||
          !audience_matches?(claims["aud"], auth_config[:audience]) ->
        {:error, :invalid_audience}

      true ->
        {:ok, claims}
    end
  end

  def validate_claims(%{"sub" => subject}) when not is_binary(subject) or subject == "",
    do: {:error, :missing_subject}

  def validate_claims(%{"sub" => _subject}), do: {:error, :missing_expiration}
  def validate_claims(_claims), do: {:error, :missing_subject}

  defp audience_matches?(audience, expected) when is_binary(audience), do: audience == expected
  defp audience_matches?(audiences, expected) when is_list(audiences), do: expected in audiences
  defp audience_matches?(_audience, _expected), do: false
end
