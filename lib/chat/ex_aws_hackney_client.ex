defmodule Chat.ExAwsHackneyClient do
  @moduledoc """
  ExAws HTTP client adapter compatible with Hackney 4.x.

  Hackney returns a three-element tuple for bodyless responses such as HEAD,
  while the stock ExAws adapter only handles the response tuple with a body.
  """

  @behaviour ExAws.Request.HttpClient

  @default_options [recv_timeout: 30_000]

  @impl true
  def request(method, url, body \\ "", headers \\ [], http_opts \\ []) do
    options =
      Application.get_env(:ex_aws, :hackney_opts, @default_options)
      |> Keyword.merge(http_opts)

    case :hackney.request(method, url, headers, body, options) do
      {:ok, status, response_headers, response_body} ->
        {:ok, response(status, response_headers, response_body)}

      {:ok, status, response_headers} ->
        {:ok, response(status, response_headers, "")}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end

  defp response(status, headers, body) do
    %{status_code: status, headers: headers, body: body}
  end
end
