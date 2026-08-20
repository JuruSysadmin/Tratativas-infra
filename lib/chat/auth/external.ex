defmodule Chat.Auth.External do
  @moduledoc false

  def request_token(username, password, request_options \\ []) do
    url = auth_server_url() <> "/api/auth/login"
    options = Keyword.merge([json: %{username: username, password: password}], request_options)

    case Req.post(url, options) do
      {:ok, %{status: 200, body: %{"token" => token} = body}} ->
        {:ok, token, body}

      {:ok, %{status: 200, body: %{"access_token" => token} = body}} ->
        {:ok, token, body}

      {:ok, %{status: 401}} ->
        {:error, :invalid_credentials}

      {:ok, %{status: _status}} ->
        {:error, :auth_server_error}

      {:error, _reason} ->
        {:error, :auth_server_error}
    end
  end

  def refresh(refresh_token, request_options \\ []) do
    url = auth_server_url() <> "/api/auth/refresh"
    options = Keyword.merge([json: %{refreshToken: refresh_token}], request_options)

    case Req.post(url, options) do
      {:ok, %{status: 200, body: %{"token" => token} = body}} -> {:ok, token, body}
      {:ok, %{status: 200, body: %{"access_token" => token} = body}} -> {:ok, token, body}
      {:ok, %{status: 401}} -> {:error, :invalid_token}
      {:ok, %{status: _status}} -> {:error, :auth_server_error}
      {:error, _reason} -> {:error, :auth_server_error}
    end
  end

  defp auth_server_url do
    :chat
    |> Application.fetch_env!(:auth)
    |> Keyword.fetch!(:server_url)
    |> String.trim_trailing("/")
  end
end
