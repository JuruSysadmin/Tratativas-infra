defmodule Chat.AI.Ollama do
  @moduledoc """
  Client for the local Ollama chat API.
  """

  @type error :: {:http_error, non_neg_integer(), term()} | :invalid_response | term()

  @spec chat(String.t(), keyword()) :: {:ok, String.t()} | {:error, error()}
  def chat(prompt, opts \\ []) when is_binary(prompt) do
    config = Application.get_env(:chat, :ollama, [])
    endpoint = Keyword.get(opts, :endpoint, Keyword.get(config, :endpoint))
    model = Keyword.get(opts, :model, Keyword.get(config, :model))

    request_options =
      config
      |> Keyword.get(:request_options, [])
      |> Keyword.merge(Keyword.drop(opts, [:endpoint, :model]))

    payload = %{
      "model" => model,
      "stream" => false,
      "messages" => [%{"role" => "user", "content" => prompt}]
    }

    case Req.post(endpoint, Keyword.put(request_options, :json, payload)) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        case get_in(body, ["message", "content"]) do
          content when is_binary(content) -> {:ok, content}
          _ -> {:error, :invalid_response}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
