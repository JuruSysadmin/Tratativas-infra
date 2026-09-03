defmodule ChatWeb.AIController do
  @moduledoc "HTTP endpoint for asking the local project AI."

  use ChatWeb, :controller

  alias Chat.AI.Ollama

  def ask(conn, %{"prompt" => prompt}) when is_binary(prompt) do
    if String.trim(prompt) == "" do
      invalid_prompt(conn)
    else
      case Ollama.chat(prompt) do
        {:ok, answer} -> json(conn, %{answer: answer})
        {:error, _reason} -> llm_unavailable(conn)
      end
    end
  end

  def ask(conn, _params), do: invalid_prompt(conn)

  defp invalid_prompt(conn) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "invalid_prompt"})
  end

  defp llm_unavailable(conn) do
    conn
    |> put_status(:bad_gateway)
    |> json(%{error: "llm_unavailable"})
  end
end
