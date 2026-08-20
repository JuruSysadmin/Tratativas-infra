defmodule Chat.TzdataHTTPClient do
  @moduledoc """
  HTTP adapter used by Tzdata without depending on Hackney's legacy API.
  """

  @behaviour Tzdata.HTTPClient

  @impl true
  def get(url, headers, options) do
    request(:get, url, headers, options)
  end

  @impl true
  def head(url, headers, options) do
    request(:head, url, headers, options)
  end

  defp request(method, url, headers, options) do
    request_options = [
      method: method,
      url: url,
      headers: headers,
      redirect: Keyword.get(options, :follow_redirect, true)
    ]

    request_options
    |> Keyword.merge(Application.get_env(:chat, :tzdata_http_client_options, []))
    |> Req.request()
    |> case do
      {:ok, response} ->
        response = Req.Response.to_map(response)

        case method do
          :get -> {:ok, {response.status, response.headers, response.body}}
          :head -> {:ok, {response.status, response.headers}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
